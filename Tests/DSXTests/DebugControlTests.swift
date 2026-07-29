// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

#if os(Android)
internal import Android
#elseif os(Linux)
internal import Glibc
#endif
#if os(Android) || os(Linux)
internal import DSXShims
#endif

#if !os(Windows)
@Suite
internal struct UnixDebugSupportTests {
  @Test
  internal func status() {
    let process = ProcessIdentifier(rawValue: 7)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 7))
    if case .stopped(let stop) =
        Debuggee.Event(status: 5 << 8 | 0x7f, process: process) {
      #expect(stop.thread == thread)
      #expect(stop.reason == .trace)
    } else {
      Issue.record("wait status did not report a stop")
    }
    if case .exited(let identifier, .exited(3)) =
        Debuggee.Event(status: 3 << 8, process: process) {
      #expect(identifier == process)
    } else {
      Issue.record("wait status did not report an exit")
    }
    if case .exited(let identifier, .signalled(9)) =
        Debuggee.Event(status: 9, process: process) {
      #expect(identifier == process)
    } else {
      Issue.record("wait status did not report a signal")
    }
  }

  @Test
  internal func watchpoint() {
    let process = ProcessIdentifier(rawValue: 7)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 9))
    let first =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x100c), size: 4,
                       kind: .watchpoint(.write))
    let second =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x1013), size: 4,
                       kind: .watchpoint(.write))
    let breakpoints = [ActiveBreakpoint(site: first, thread: nil),
                       ActiveBreakpoint(site: second, thread: nil)]
    #expect(breakpoints.nearest(0x1000, thread: thread) == 0)
    #expect(breakpoints.nearest(0x1014, thread: thread) == 1)
    #expect(breakpoints.nearest(0x1011, thread: thread) == nil)
  }
}
#endif

#if os(Android) || os(Linux)
@Suite
internal struct LinuxTrapTests {
  @Test
  internal func embedded() throws {
    let address = try ABI.breakpoint(0x1001)
    var information = siginfo_t()
    information.si_code = TRAP_BRKPT
    let trap = try information.trap(program: 0x1001, fallback: .trace)
    #expect(trap.address == address)
    #expect(trap.reason == .breakpoint)

    information.si_code = TRAP_TRACE
    let step = try information.trap(program: 0x1001, fallback: .signal(SIGTRAP))
    #expect(step.address == 0x1001)
    #expect(step.reason == .trace)

    information.si_code = SI_TKILL
    let raised = try information.trap(program: 0x1001, fallback: .trace)
    #expect(raised.address == 0x1001)
    #expect(raised.reason == .signal(SIGTRAP))

    information.si_code = SI_USER
    let fallback =
        try information.trap(program: 0x1001, fallback: .signal(SIGTRAP),
                             stepping: true)
    #expect(fallback.address == 0x1001)
    #expect(fallback.reason == .trace)

    information.si_code = TRAP_BRKPT
    let interrupted =
        try information.trap(program: 0x1001, fallback: .trace, stepping: true)
    #expect(interrupted.address == address)
    #expect(interrupted.reason == .breakpoint)
  }

  @Test
  internal func completion() {
    var information = siginfo_t()
    var registers = LinuxGeneralRegisters()
    registers.set(pc: 0x1004)
    information.si_code = TRAP_TRACE
    #expect(information.completes(registers, at: 0x1004))
    #expect(information.pending(registers, at: 0x1004))
    #expect(information.pending(registers, at: 0x1008) == false)
    #expect(information.completes(registers, at: 0x1008) == false)
    information.si_code = SI_TKILL
    #expect(information.completes(registers, at: 0x1004) == false)
    information.si_code = TRAP_HWBKPT
    #expect(information.completes(registers, at: 0x1004) == false)
    #expect(information.pending(registers, at: 0x1004) == false)
    information.si_code = TRAP_BRKPT
#if arch(i386) || arch(x86_64)
    #expect(information.completes(registers, at: 0x1004))
    #expect(information.pending(registers, at: 0x1004))
#else
    #expect(information.completes(registers, at: 0x1004) == false)
    #expect(information.pending(registers, at: 0x1004) == false)
#endif
    #expect(information.pending(registers, at: 0x1008) == false)
    information.si_code = SI_USER
#if arch(arm64)
    #expect(information.completes(registers, at: 0x1004))
#else
    #expect(information.completes(registers, at: 0x1004) == false)
#endif
    #expect(information.pending(registers, at: 0x1004))
    #expect(information.pending(registers, at: 0x1008) == false)
  }

#if os(Linux)
  @Test
  internal func provenance() {
    var information = siginfo_t()
    information.si_code = SI_USER
    information._sifields._kill.si_pid = 42
    var registers = LinuxGeneralRegisters()
    registers.set(pc: 0x1004)
    #expect(information.completes(registers, at: 0x1004) == false)
    #expect(information.completes(registers, at: 0x1008) == false)
    #expect(information.pending(registers, at: 0x1004) == false)
  }
#endif

  @Test
  internal func information() throws {
    var information = siginfo_t()
    information.si_code = SI_USER
    #expect(information.generated(by: 0))
    #expect(information.generated(by: 1) == false)
    #expect(information.address(SIGSEGV) == false)
    information.si_code = TRAP_TRACE
    #expect(information.generated(by: 0) == false)
    information.si_code = SEGV_MAPERR
    #expect(information.address(SIGSEGV))
    #expect(information.address(SIGTRAP) == false)
    information.si_code = BUS_ADRALN
    #expect(information.address(SIGBUS))
    information.si_code = SI_KERNEL
    #expect(information.address(SIGSEGV))
    #expect(information.address(SIGBUS) == false)
    for code in [DSX::BUS_MCEERR_AR, DSX::BUS_MCEERR_AO] {
      information.si_code = code
      #expect(information.address(SIGBUS))
    }
    for code in [SEGV_MTEAERR, SEGV_MTESERR, SEGV_CPERR] {
      information.si_code = code
      #expect(information.address(SIGSEGV))
    }
    information.si_code = TRAP_HWBKPT
    let trap = try information.trap(program: 0x1004, fallback: .trace)
    #expect(trap.address == 0)
    #expect(trap.reason == .trace)
  }
}

@Suite
internal struct LinuxDebugControlTests {
  @Test
  internal func running() throws {
    let process = ProcessIdentifier(rawValue: UInt64(Int32.max))
    var control = LinuxDebugControl()
    control.process = process
    control.threads = [Int32.max: LinuxThreadState(process: process,
                                                   stepping: true)]
    let actions = [Debuggee.Continuation(selection: .all, operation: .resume,
                                         signal: 0)]
    try control.resume(actions.span)
    #expect(control.threads[Int32.max]?.stopped == false)
    #expect(control.threads[Int32.max]?.stepping == true)
  }

  @Test
  internal func interrupt() throws {
    let process = ProcessIdentifier(rawValue: 7)
    var control = LinuxDebugControl()
    control.process = process
    control.threads = [
      7: LinuxThreadState(process: process, stopped: true),
      8: LinuxThreadState(process: process, stopped: true),
    ]
    control.requested = true
    control.obsolete = true

    try control.interrupt(process)

    guard case .stopped(let stop) = try control.event() else {
      Issue.record("interrupt did not synthesize a stop")
      return
    }
    let thread = ThreadIdentifier(rawValue: 7)
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    #expect(stop.thread == identifier)
    #expect(stop.reason == .interrupt)
    #expect(control.requested == false)
    #expect(control.obsolete == false)
  }

  @Test
  internal func termination() throws {
    let process = ProcessIdentifier(rawValue: 7)
    var control = LinuxDebugControl()
    control.process = process
    control.threads = [
      7: LinuxThreadState(process: process, stopped: true),
      8: LinuxThreadState(process: process, stopped: true),
    ]
    control.threads[8]?.newborn = true
    control.threads[8]?.entry = true
    control.threads[8]?.stepping = true
    control.status = 0
    control.thread = 8

    guard case .terminated(let thread, 0) = try control.event() else {
      Issue.record("thread exit was not reported")
      return
    }
    let native = ThreadIdentifier(rawValue: 8)
    let identifier = ProcessThreadIdentifier(process: process, thread: native)
    #expect(thread == identifier)
    #expect(control.threads.count == 1)
    #expect(control.threads[7]?.process == process)
    #expect(control.threads[7]?.stopped == true)
    #expect(control.threads[7]?.newborn == false)
    #expect(control.threads[7]?.entry == false)
    #expect(control.threads[7]?.stepping == false)
  }

  @Test
  internal func exit() throws {
    let process = ProcessIdentifier(rawValue: 7)
    var control = LinuxDebugControl()
    control.process = process
    control.threads = [7: LinuxThreadState(process: process, stopped: true)]
    control.status = 0
    control.thread = 7

    guard case .exited(let identifier, .exited(0)) = try control.event() else {
      Issue.record("process exit was not reported")
      return
    }
    #expect(identifier == process)
    #expect(control.process == nil)
    #expect(control.threads.isEmpty)
  }

  @Test
  internal func promotion() throws {
    let parent = ProcessIdentifier(rawValue: 7)
    let child = ProcessIdentifier(rawValue: 8)
    var control = LinuxDebugControl()
    control.process = parent
    control.children = [8]
    control.threads = [
      7: LinuxThreadState(process: parent),
      8: LinuxThreadState(process: child),
    ]
    control.status = 0
    control.thread = 7

    guard case .exited(let identifier, .exited(0)) = try control.event() else {
      Issue.record("parent exit was not reported")
      return
    }
    #expect(identifier == parent)
    #expect(control.process == child)
    #expect(control.children.isEmpty)
    #expect(control.threads.count == 1)
    #expect(control.threads[8]?.process == child)
  }
}
#endif

@Suite
internal struct HardwareBreakpointTests {
  @Test
  internal func advancement() {
    #expect(HardwareBreakpoint.advance(.hardware)
        == HardwareBreakpoint.supports(.hardware))
    #expect(HardwareBreakpoint.advance(.software) == false)
#if os(Windows)
    #expect(HardwareBreakpoint.advance(.watchpoint(.readwrite)))
#else
    #expect(HardwareBreakpoint.advance(.watchpoint(.readwrite)) == false)
#endif
  }
}

#if arch(arm64)
@Suite
internal struct ARM64BreakpointControlTests {
  @Test
  internal func breakpoint() throws {
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x1000), size: 4,
                       kind: .hardware)
    let encoded = try ARM64BreakpointControl(site)
    #expect(encoded.address == 0x1000)
    #expect(encoded.control & 1 == 1)
    #expect(encoded.control >> 5 & 0xff == 0x0f)
  }

  @Test
  internal func watchpoint() throws {
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x1003), size: 2,
                       kind: .watchpoint(.readwrite))
    let encoded = try ARM64BreakpointControl(site)
    #expect(encoded.address == 0x1000)
    #expect(encoded.control & 1 == 1)
    #expect(encoded.control >> 3 & 0x3 == 0x3)
    #expect(encoded.control >> 5 & 0xff == 0x18)
    #expect(encoded.matches(address: 0x1000, control: encoded.control ^ 0x6))
    #expect(encoded.matches(address: 0x1008, control: encoded.control) == false)
  }

  @Test
  internal func straddling() {
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x1007), size: 2,
                       kind: .watchpoint(.write))
    #expect(throws: Debuggee.Error.breakpoint) {
      try ARM64BreakpointControl(site)
    }
    let controls = try? ARM64BreakpointControl.partition(site)
    #expect(controls?.first.contains(0x1007) == true)
    #expect(controls?.second?.contains(0x1008) == true)
  }

  @Test
  internal func range() throws {
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x4000), size: 1024,
                       kind: .watchpoint(.write))
    let encoded = try ARM64BreakpointControl(site)
    #expect(encoded.address == 0x4000)
    #expect(encoded.control >> 24 & 0x1f == 10)
    #expect(encoded.contains(0x43ff))
    #expect(encoded.contains(0x4400) == false)
  }
}
#endif

#if arch(i386) || arch(x86_64)
@Suite
internal struct X86BreakpointControlTests {
  @Test
  internal func identity() throws {
    let address = Debuggee.Address(rawValue: 0x1000)
    let execution = BreakpointSite(address: address, size: 1, kind: .hardware)
    let byte =
        BreakpointSite(address: address, size: 1, kind: .watchpoint(.write))
    let word =
        BreakpointSite(address: address, size: 4, kind: .watchpoint(.write))
    let execute = try X86BreakpointControl(execution)
    let first = try X86BreakpointControl(byte)
    let second = try X86BreakpointControl(word)
    var control: X86BreakpointControl.Word = 0
    #expect(execute.matches(control, slot: 0) == false)
    execute.enable(0, control: &control)
    first.enable(1, control: &control)
    second.enable(2, control: &control)
    #expect(execute.matches(control, slot: 0))
    #expect(first.matches(control, slot: 0) == false)
    #expect(first.matches(control, slot: 1))
    #expect(second.matches(control, slot: 1) == false)
    #expect(second.matches(control, slot: 2))
    X86BreakpointControl.disable(1, control: &control)
    #expect(execute.matches(control, slot: 0))
    #expect(first.matches(control, slot: 1) == false)
    #expect(second.matches(control, slot: 2))
  }

  @Test
  internal func breakpoint() throws {
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x1000), size: 1,
                       kind: .hardware)
    let encoded = try X86BreakpointControl(site)
    #expect(encoded.control == 0)
  }

  @Test
  internal func watchpoint() throws {
    #if arch(i386)
    let size = 4
    let expected: X86BreakpointControl.Word = 0xf
    #else
    let size = 8
    let expected: X86BreakpointControl.Word = 0xb
    #endif
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x1008), size: size,
                       kind: .watchpoint(.readwrite))
    let encoded = try X86BreakpointControl(site)
    #expect(encoded.control == expected)
  }

  @Test
  internal func acknowledgement() {
    let status: X86BreakpointControl.Word = 0b1111
    #expect(X86BreakpointControl.acknowledge(status, slot: 2) == 0b1011)
  }

  @Test
  internal func alignment() {
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x1001), size: 4,
                       kind: .watchpoint(.write))
    #expect(throws: Debuggee.Error.breakpoint) {
      try X86BreakpointControl(site)
    }
  }
}
#endif

#if os(anyAppleOS)
internal import Darwin

@Suite
internal struct DarwinDebugControlTests {
  @Test(arguments: [false, true])
  internal func starting(_ exited: Bool) throws {
    var arguments = [strdup("/bin/sleep"), strdup("60"), nil]
    defer {
      free(arguments[0])
      free(arguments[1])
    }
    var child: pid_t = 0
    try #require(posix_spawn(&child, "/bin/sleep", nil, nil, &arguments,
                             environ) == 0)
    let process = ProcessIdentifier(rawValue: UInt64(child))
    var session = DebugSession()
    session.control.process = process
    session.debuggee.insert(Debuggee.Process(identifier: process))
    session.state = .starting(.launched)
    defer {
      _ = DSX::kill(pid_t(process.rawValue), SIGKILL)
      _ = waitpid(pid_t(process.rawValue), nil, 0)
    }
    #expect(session.phase == .pending)
    if exited {
      try #require(DSX::kill(child, SIGKILL) == 0)
      #expect(throws: Debuggee.Error.premature(SIGKILL)) {
        try session.settle()
      }
    }
    // No initial exception has arrived. Cleanup cannot depend on receiving it.
    try session.close(cause: .failure)
    #expect(session.phase == .idle)
    #expect(DSX::kill(pid_t(process.rawValue), 0) == -1)
    #expect(errno == ESRCH)
  }

  @Test
  internal func exceptions() {
    let access = UInt32(bitPattern: EXC_MASK_BAD_ACCESS)
    let instruction = UInt32(bitPattern: EXC_MASK_BAD_INSTRUCTION)
    let arithmetic = UInt32(bitPattern: EXC_MASK_ARITHMETIC)
    let syscall = UInt32(bitPattern: EXC_MASK_SYSCALL)
    let resource = UInt32(bitPattern: EXC_MASK_RESOURCE)
    let guarded = UInt32(bitPattern: EXC_MASK_GUARD)
    #expect(Debuggee.ExceptionMask.access.rawValue == access)
    #expect(Debuggee.ExceptionMask.instruction.rawValue == instruction)
    #expect(Debuggee.ExceptionMask.arithmetic.rawValue == arithmetic)
    #expect(Debuggee.ExceptionMask.syscall.rawValue == syscall)
    #expect(Debuggee.ExceptionMask.resource.rawValue == resource)
    #expect(Debuggee.ExceptionMask.guarded.rawValue == guarded)
    #expect(Debuggee.Error(task: KERN_FAILURE, invalid: .process) == .access)
  }

  @Test(arguments: [false, true])
  internal func attach(_ stopped: Bool) throws {
    var arguments = [strdup("/bin/sleep"), strdup("10"), nil]
    defer {
      free(arguments[0])
      free(arguments[1])
    }
    var child: pid_t = 0
    let status =
        posix_spawn(&child, "/bin/sleep", nil, nil, &arguments, environ)
    #expect(status == 0)
    guard status == 0 else {
      return
    }
    defer {
      _ = DSX::kill(child, SIGKILL)
      _ = waitpid(child, nil, 0)
    }
    let process = ProcessIdentifier(rawValue: UInt64(child))
    var control = DarwinDebugControl()
    do {
      try control.attach(process)
    } catch Debuggee.Error.access {
      return
    }
    if case .stopped(let stop) = try control.event(blocking: true) {
      #expect(stop.thread.process == process)
      let action =
          Debuggee.Continuation(selection: .thread(stop.thread),
                                operation: .resume, signal: SIGUSR1)
      let actions: InlineArray<1, Debuggee.Continuation> = [action]
      #expect(throws: Debuggee.Error.unsupported) {
        try control.resume(actions.span)
      }
      let continuation =
          Debuggee.Continuation(selection: .process(process),
                                operation: .resume)
      let continuations: InlineArray<1, Debuggee.Continuation> = [continuation]
      try control.resume(continuations.span)
      try control.interrupt(process)
      guard case .stopped = try control.event(blocking: true) else {
        Issue.record("interrupt did not report a stop")
        return
      }
    } else {
      Issue.record("attach did not report a stop")
    }
    try control.detach(process, stopped: stopped)
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    try #require(proc_pidinfo(child, PROC_PIDTBSDINFO, 0, &info, size) == size)
    #expect((info.pbi_status == SSTOP) == stopped)
  }

  @Test
  internal func launch() throws {
    var control = DarwinDebugControl()
    let config = Debuggee.Launch(executable: "/usr/bin/true")
    let process: ProcessIdentifier
    do {
      process = try control.launch(config)
    } catch Debuggee.Error.access {
      return
    }
    let identifier = try process.native
    defer {
      _ = DSX::kill(identifier, SIGKILL)
      control.discard()
      _ = waitpid(identifier, nil, 0)
    }
    guard case .stopped(let stop) = try control.event(blocking: true) else {
      Issue.record("launch did not report its initial stop")
      return
    }
    #expect(stop.thread.process == process)
    #expect(stop.reason == .signal(SIGSTOP))
    try control.terminate(process)
    guard case .exited(let exited, .signalled(SIGKILL)) =
        try control.event(blocking: true) else {
      Issue.record("termination did not report its reaped exit")
      return
    }
    #expect(exited == process)
  }

  @Test
  internal func output() throws {
    var descriptors: InlineArray<2, CInt> = [-1, -1]
    let status = withUnsafeMutablePointer(to: &descriptors) { descriptors in
      descriptors.withMemoryRebound(to: CInt.self, capacity: 2) { values in
        pipe(values)
      }
    }
    #expect(status == 0)
    defer {
      _ = DSX::close(descriptors[0])
      _ = DSX::close(descriptors[1])
    }
    let flags = fcntl(descriptors[0], F_GETFL)
    #expect(flags >= 0)
    #expect(fcntl(descriptors[0], F_SETFL, flags | O_NONBLOCK) == 0)
    let bytes = Array("DSX".utf8)
    let count = bytes.withUnsafeBytes { bytes in
      DSX::write(descriptors[1], bytes.baseAddress, bytes.count)
    }
    #expect(count == bytes.count)

    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let thread = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 1))
    let stop = Debuggee.Stop(thread: thread, reason: .breakpoint)
    var control = DarwinDebugControl()
    control.process = process
    control.reader = descriptors[0]
    let event =
        try control.enqueue(.stopped(stop), process: process, output: true)
    guard case .output(let identifier) = event else {
      Issue.record("output did not precede the stop")
      return
    }
    var captured = Array<UInt8>()
    let capacity = Configuration.OutputCapacity
    try captured.append(addingCapacity: capacity) { output in
      try control.output(identifier, into: &output)
    }
    #expect(captured == bytes)
    guard case .stopped = try control.event() else {
      Issue.record("trap did not follow output")
      return
    }
  }

  @Test
  internal func exit() throws {
    var descriptors: InlineArray<2, CInt> = [-1, -1]
    let status = withUnsafeMutablePointer(to: &descriptors) { descriptors in
      descriptors.withMemoryRebound(to: CInt.self, capacity: 2) { values in
        pipe(values)
      }
    }
    #expect(status == 0)
    defer {
      if descriptors[0] >= 0 {
        _ = DSX::close(descriptors[0])
      }
      if descriptors[1] >= 0 {
        _ = DSX::close(descriptors[1])
      }
    }
    let bytes = Array("DSX".utf8)
    let count = bytes.withUnsafeBytes { bytes in
      DSX::write(descriptors[1], bytes.baseAddress, bytes.count)
    }
    #expect(count == bytes.count)

    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    var control = DarwinDebugControl()
    control.process = process
    control.reader = descriptors[0]
    let event = try control.enqueue(.exited(process, .exited(0)),
                                    process: process, output: true)
    guard case .output(let identifier) = event else {
      Issue.record("output did not precede the exit")
      return
    }
    _ = DSX::close(descriptors[1])
    descriptors[1] = -1
    var captured = Array<UInt8>()
    let capacity = Configuration.OutputCapacity
    try captured.append(addingCapacity: capacity) { output in
      try control.output(identifier, into: &output)
    }
    #expect(captured == bytes)
    guard case .exited(let exited, .exited(0)) = try control.event() else {
      Issue.record("exit did not follow output")
      return
    }
    descriptors[0] = -1
    #expect(exited == process)
    #expect(control.process == nil)
  }
}
#endif
