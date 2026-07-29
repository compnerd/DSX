// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims
internal import Testing
@testable internal import DSX

@Suite internal struct DarwinEventTests {
  @Test
  internal func readiness() throws {
    var port = mach_port_t(MACH_PORT_NULL)
    try #require(mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE,
                                    &port) == KERN_SUCCESS)
    defer {
      _ = mach_port_mod_refs(mach_task_self_, port, MACH_PORT_RIGHT_RECEIVE, -1)
    }
    let inserted =
        mach_port_insert_right(mach_task_self_, port, port,
                               mach_msg_type_name_t(MACH_MSG_TYPE_MAKE_SEND))
    try #require(inserted == KERN_SUCCESS)
    defer { _ = mach_port_deallocate(mach_task_self_, port) }
    var queue = try DarwinEventQueue(port, process: getpid())
    var descriptor =
        pollfd(fd: queue.descriptor, events: Int16(POLLIN), revents: 0)
    #expect(fcntl(queue.descriptor, F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
    #expect(poll(&descriptor, 1, 0) == 0)
    var message = mach_msg_header_t()
    message.msgh_bits = mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND)
    message.msgh_remote_port = port
    message.msgh_size = mach_msg_size_t(MemoryLayout.size(ofValue: message))
    let sent = mach_msg(&message, MACH_SEND_MSG, message.msgh_size, 0,
                        mach_port_t(MACH_PORT_NULL), 0,
                        mach_port_t(MACH_PORT_NULL))
    try #require(sent == KERN_SUCCESS)
    #expect(poll(&descriptor, 1, 1000) == 1)
    try queue.drain()
    // Acknowledging the wakeup must leave the exception for its owner.
    #expect(poll(&descriptor, 1, 0) == 1)
    var received = mach_msg_empty_rcv_t()
    let status = withUnsafeMutablePointer(to: &received) {
      $0.withMemoryRebound(to: mach_msg_header_t.self, capacity: 1) {
        mach_msg($0, MACH_RCV_MSG | MACH_RCV_TIMEOUT, 0,
                 mach_msg_size_t(MemoryLayout<mach_msg_empty_rcv_t>.size),
                 port, 0, mach_port_t(MACH_PORT_NULL))
      }
    }
    #expect(status == KERN_SUCCESS)
    try queue.drain()
    #expect(queue.exited == false)
    #expect(poll(&descriptor, 1, 0) == 0)
  }

  @Test
  internal func termination() throws {
    var port = mach_port_t(MACH_PORT_NULL)
    try #require(mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_RECEIVE,
                                    &port) == KERN_SUCCESS)
    defer {
      _ = mach_port_mod_refs(mach_task_self_, port, MACH_PORT_RIGHT_RECEIVE, -1)
    }
    var attributes: posix_spawnattr_t?
    try #require(posix_spawnattr_init(&attributes) == 0)
    defer { _ = posix_spawnattr_destroy(&attributes) }
    let flags =
        posix_spawnattr_setflags(&attributes, DSX::POSIX_SPAWN_START_SUSPENDED)
    try #require(flags == 0)
    var process: pid_t = 0
    let status = "/usr/bin/true".withCString { path in
      var arguments = [UnsafeMutablePointer(mutating: path), nil]
      return posix_spawn(&process, path, nil, &attributes, &arguments, nil)
    }
    try #require(status == 0)
    defer {
      _ = DSX::kill(process, SIGKILL)
      _ = waitpid(process, nil, 0)
    }
    var queue = try DarwinEventQueue(port, process: process)
    var descriptor =
        pollfd(fd: queue.descriptor, events: Int16(POLLIN), revents: 0)
    #expect(poll(&descriptor, 1, 0) == 0)
    try #require(DSX::kill(process, SIGCONT) == 0)
    // An exit without any Mach exception must still wake an indefinite wait.
    #expect(poll(&descriptor, 1, 5000) == 1)
    // Preserve exit readiness until the controller reaps and releases it.
    #expect(poll(&descriptor, 1, 0) == 1)
    try queue.drain()
    #expect(queue.exited == true)
    #expect(poll(&descriptor, 1, 0) == 0)
    try queue.drain()
    #expect(queue.exited == true)
  }

  @Test(arguments: 0 ..< 16)
  internal func loader(_: Int) throws(Debuggee.Error) {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    for _ in 0 ..< 16 {
      #expect(try process.loader.state == .running)
    }
  }

  @Test
  internal func registers() throws {
    let current = ProcessIdentifier(rawValue: UInt64(getpid()))
    let image = try current.image
    let executable = try #require(image)
    var control = DarwinDebugControl()
    let process =
        try control.launch(Debuggee.Launch(executable: executable.path))
    let identifier = try process.native
    defer {
      _ = DSX::kill(identifier, SIGKILL)
      control.discard()
      _ = waitpid(identifier, nil, 0)
    }
    guard case let .stopped(stop) =
        try control.event(blocking: true, output: false) else {
      Issue.record("launch did not stop")
      return
    }
    let saved = try SavedRegisters(stop.thread, control: control)
    var registers = try NativeRegisterState(stop.thread, control: control)
    let address = try registers.pc
    try registers.set(pc: address)
    // PC correction must not attempt to write the kernel's exception bank.
    try registers.commit()
    var restored = try NativeRegisterState(stop.thread, control: control)
    try restored.restore(saved)
    #expect(try restored.pc == address)
    try restored.commit()

    var snapshot = try NativeRegisterState(stop.thread, control: control)
    let description = RegisterDescription(snapshot.configuration)
    var count = 0
    for index in 0 ..< description.count {
      let record = try #require(description.register(index))
      if NativeRegisterState.access(record.identifier) == .mutable {
        continue
      }
      count += 1
      try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: record.bytes,
                                        { buffer in
        var output = OutputSpan(buffer: buffer, initializedCount: 0)
        if NativeRegisterState.access(record.identifier) == .unavailable {
          #expect(throws: Debuggee.Error.register) {
            try snapshot.read(record.identifier, into: &output)
          }
          #expect(output.count == 0)
        } else {
          try snapshot.read(record.identifier, into: &output)
          #expect(output.count == record.bytes)
        }
        output.removeAll()
        for _ in 0 ..< record.bytes {
          output.append(0)
        }
        #expect(throws: Debuggee.Error.register) {
          try snapshot.write(record.identifier, bytes: output.span)
        }
        let packet =
            Array(repeating: UInt8(ascii: "f"), count: record.bytes * 2)
        var reader = GDBPacketReader(packet.span)
        try reader.apply(to: &snapshot, register: record, model: description,
                         restoring: true, scratch: &output)
        #expect(reader.empty == true)
        #expect(output.count == 0)
        var explicit = GDBPacketReader(packet.span)
        #expect(throws: GDBHandlerError.debuggee(.register)) {
          try explicit.apply(to: &snapshot, register: record,
                             model: description, scratch: &output)
        }
        let unavailable =
            Array(repeating: UInt8(ascii: "x"), count: record.bytes * 2)
        var ignored = GDBPacketReader(unavailable.span)
        try ignored.apply(to: &snapshot, register: record, model: description,
                          restoring: true, scratch: &output)
        #expect(ignored.empty == true)
        #expect(output.count == 0)
      })
    }
#if arch(x86_64)
    #expect(count == 6)
    let unavailable = try (19 ... 21).map { index in
      try #require(description.register(index))
    }
    for record in unavailable {
      try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 9, { buffer in
        var writer =
            GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
        try writer.append(UInt8(ascii: ";"))
        try writer.emit(snapshot, register: record, model: description)
        let text = String(decoding: writer.output.span, as: UTF8.self)
        #expect(text == ";xxxxxxxx")
        #expect(throws: GDBHandlerError.capacity) {
          try writer.emit(snapshot, register: record, model: description)
        }
      })
    }
#else
    #expect(count == 3)
#endif
    // An invalid register is an error, not an unavailable native value.
    let storage = RegisterStorage(UInt64(UInt16.max), 32, 0, relations: 0)
    let invalid = RegisterRecord(storage: storage, index: description.count)
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 9, { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      try writer.append(UInt8(ascii: ";"))
      #expect(throws: GDBHandlerError.debuggee(.register)) {
        try writer.emit(snapshot, register: invalid, model: description)
      }
      let text = String(decoding: writer.output.span, as: UTF8.self)
      #expect(text == ";")
    })
  }

  @Test
  internal func interrupt() throws {
    let process = ProcessIdentifier(rawValue: UInt64(pid_t.max))
    var control = DarwinDebugControl()
    control.process = process
    control.requested = true
    control.obsolete = true
    // An outstanding signal satisfies a renewed request. Sending it again
    // would leave two native stops behind one pending-interrupt flag.
    try control.interrupt(process)
    #expect(control.requested)
    #expect(control.obsolete == false)
  }

  @Test(arguments: [Debuggee.StopReason.breakpoint, .trace])
  internal func unclaimed(_ reason: Debuggee.StopReason) throws {
    let identifier =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    let data = Debuggee.ExceptionData(count: 2) { UInt64($0 + 1) }
    let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: 0x1000),
                               code: UInt64(EXC_BREAKPOINT), data: data,
                               domain: .mach)
    let control = DarwinDebugControl()
    let table = BreakpointTable()
    let stop = Debuggee.Stop(thread: identifier, reason: reason, fault: fault)
    let result = try table.classify(stop, control: control)
    let expected: Debuggee.StopReason = reason == .breakpoint
        ? .exception(UInt64(EXC_BREAKPOINT)) : .trace
    #expect(result.reason == expected)
    #expect(result.fault?.address == fault.address)
    #expect(result.breakpoint == nil)

    let breakpoint = BreakpointIdentifier(rawValue: 3)
    let owned = Debuggee.Stop(thread: identifier, reason: reason, fault: fault,
                              breakpoint: breakpoint)
    let retained = try table.classify(owned, control: control)
    #expect(retained.reason == reason)
    #expect(retained.breakpoint == breakpoint)
  }

#if arch(arm64)
  @Test
  internal func stepping() throws {
    let current = ProcessIdentifier(rawValue: UInt64(getpid()))
    let image = try current.image
    let executable = try #require(image)
    var control = DarwinDebugControl()
    let process =
        try control.launch(Debuggee.Launch(executable: executable.path))
    let identifier = try process.native
    defer {
      _ = DSX::kill(identifier, SIGKILL)
      control.discard()
      _ = waitpid(identifier, nil, 0)
    }
    guard case let .stopped(initial) =
        try control.event(blocking: true, output: false) else {
      Issue.record("launch did not stop")
      return
    }
    let thread = try DarwinThread(initial.thread, control: control)
    var state = try arm_thread_state64_t(thread.handle)
    // dyld aligns its incoming stack before accessing it through SP.
    state.__sp &= ~0x000f
    let address = Debuggee.Address(rawValue: state.__pc)
    // nop; str w0, [sp]; brk #0. No runtime or dynamic linker is executed.
    let instructions: InlineArray<3, UInt32> = [
      0xd503201f, 0xb90003e0, 0xd4200000,
    ]
    var written = 0
    try withUnsafeBytes(of: instructions) { bytes in
      let bytes = bytes.bindMemory(to: UInt8.self)
      try DarwinMemory.write(process, address: address, bytes: bytes.span,
                             count: &written, control: control)
    }
    try #require(written == 12)
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: state.__sp), size: 4,
                       kind: .watchpoint(.write))
    try control.breakpoint(process, site: site, thread: nil, enabled: true)
    let step: InlineArray<1, Debuggee.Continuation> = [
      Debuggee.Continuation(selection: .thread(initial.thread),
                            operation: .step),
    ]
    let resume: InlineArray<1, Debuggee.Continuation> = [
      Debuggee.Continuation(selection: .process(process), operation: .resume),
    ]
    for _ in 0 ..< 200 {
      try thread.handle.write(state, flavor: ARM_THREAD_STATE64)
      try control.resume(step.span)
      guard case let .stopped(stepped) =
          try control.event(blocking: true, output: false) else {
        Issue.record("single step did not stop")
        return
      }
      try #require(stepped.reason == .trace)
      try #require(arm_thread_state64_t(thread.handle).__pc == state.__pc + 4)
      try control.resume(resume.span)
      guard case let .stopped(watched) =
          try control.event(blocking: true, output: false) else {
        Issue.record("watchpoint did not stop")
        return
      }
      try #require(watched.reason == .watchpoint(.write, site.address))
    }
  }

  @Test(arguments: [true, false])
  internal func watchpoint(_ owned: Bool) throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let threads = try DarwinThreadList(process)
    let thread = mach_thread_self()
    defer { _ = mach_port_deallocate(mach_task_self_, thread) }
    var record = dsx_exception_record()
    record.thread = thread
    record.type = EXC_BREAKPOINT
    record.count = 2
    record.codes = (Int64(EXC_ARM_DA_DEBUG), 0x1002)
    let site = BreakpointSite(address: Debuggee.Address(rawValue: 0x1000),
                              size: 4, kind: .watchpoint(.write))
    let sites = owned ? [ActiveBreakpoint(site: site, thread: nil)] : []
    let event = try Debuggee.Event(record, process: process, threads: threads,
                                   breakpoints: sites)
    guard case let .stopped(stop) = event else {
      Issue.record("Mach data breakpoint must report a stop")
      return
    }
    let reason: Debuggee.StopReason =
        owned ? .watchpoint(.write, site.address)
              : .exception(UInt64(EXC_BREAKPOINT))
    #expect(stop.reason == reason)
    #expect(try stop.thread.thread == ThreadIdentifier(mach: thread))
    #expect(stop.fault?.address.rawValue == 0x1002)
    #expect(stop.fault?.code == UInt64(EXC_BREAKPOINT))
  }
#endif

  @Test internal func outputFailureRetainsExit() throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    var control = DarwinDebugControl()
    control.process = process
    control.status = 0
    control.reader = -1
    #expect(throws: Debuggee.Error.self) {
      try control.event()
    }
    let event = try control.event(output: false)
    guard case let .exited(identifier, _) = event else {
      Issue.record("The reaped exit must remain available after a read failure")
      return
    }
    #expect(identifier == process)
    #expect(control.process == nil)
    #expect(control.deferred == nil)
  }
}
#endif
