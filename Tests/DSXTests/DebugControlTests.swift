// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

#if os(Android)
internal import Android
#elseif os(Linux)
internal import Glibc
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
        UnixWaitStatus.event(5 << 8 | 0x7f, process: process) {
      #expect(stop.thread == thread)
      #expect(stop.reason == .trace)
    } else {
      Issue.record("wait status did not report a stop")
    }
    if case .exited(let identifier, .exited(3)) =
        UnixWaitStatus.event(3 << 8, process: process) {
      #expect(identifier == process)
    } else {
      Issue.record("wait status did not report an exit")
    }
    if case .exited(let identifier, .signalled(9)) =
        UnixWaitStatus.event(9, process: process) {
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
    let trap =
        try LinuxDebugControl.trap(TRAP_BRKPT, program: 0x1001,
                                   fallback: .trace)
    #expect(trap.address == address)
    #expect(trap.reason == .breakpoint)

    let step =
        try LinuxDebugControl.trap(TRAP_TRACE, program: 0x1001,
                                   fallback: .signal(SIGTRAP))
    #expect(step.address == 0x1001)
    #expect(step.reason == .trace)

    let raised =
        try LinuxDebugControl.trap(-6, program: 0x1001, fallback: .trace)
    #expect(raised.address == 0x1001)
    #expect(raised.reason == .signal(SIGTRAP))

    let fallback =
        try LinuxDebugControl.trap(0, program: 0x1001,
                                   fallback: .signal(SIGTRAP), stepping: true)
    #expect(fallback.address == 0x1001)
    #expect(fallback.reason == .trace)

    let interrupted =
        try LinuxDebugControl.trap(TRAP_BRKPT, program: 0x1001,
                                   fallback: .trace, stepping: true)
    #expect(interrupted.address == address)
    #expect(interrupted.reason == .breakpoint)
  }
}

@Suite
internal struct LinuxDebugControlTests {
  @Test
  internal func interrupt() throws {
    let process = ProcessIdentifier(rawValue: 7)
    var control = LinuxDebugControl()
    control.process = process
    control.owners = [7: process, 8: process]
    control.stopped = [7, 8]
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
    control.owners = [7: process, 8: process]
    control.stopped = [7, 8]
    control.newborn = [8]
    control.entries = [8]
    control.stepping = [8]
    control.status = 0
    control.thread = 8

    guard case .terminated(let thread, 0) = try control.event() else {
      Issue.record("thread exit was not reported")
      return
    }
    let native = ThreadIdentifier(rawValue: 8)
    let identifier = ProcessThreadIdentifier(process: process, thread: native)
    #expect(thread == identifier)
    #expect(control.owners == [7: process])
    #expect(control.stopped == [7])
    #expect(control.newborn.isEmpty)
    #expect(control.entries.isEmpty)
    #expect(control.stepping.isEmpty)
  }

  @Test
  internal func exit() throws {
    let process = ProcessIdentifier(rawValue: 7)
    var control = LinuxDebugControl()
    control.process = process
    control.owners = [7: process]
    control.stopped = [7]
    control.status = 0
    control.thread = 7

    guard case .exited(let identifier, .exited(0)) = try control.event() else {
      Issue.record("process exit was not reported")
      return
    }
    #expect(identifier == process)
    #expect(control.process == nil)
    #expect(control.owners.isEmpty)
    #expect(control.stopped.isEmpty)
  }

  @Test
  internal func promotion() throws {
    let parent = ProcessIdentifier(rawValue: 7)
    let child = ProcessIdentifier(rawValue: 8)
    var control = LinuxDebugControl()
    control.process = parent
    control.children = [8]
    control.owners = [7: parent, 8: child]
    control.status = 0
    control.thread = 7

    guard case .exited(let identifier, .exited(0)) = try control.event() else {
      Issue.record("parent exit was not reported")
      return
    }
    #expect(identifier == parent)
    #expect(control.process == child)
    #expect(control.children.isEmpty)
    #expect(control.owners == [8: child])
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
    let encoded = try ARM64BreakpointControl.encode(site)
    #expect(encoded.address == 0x1000)
    #expect(encoded.control & 1 == 1)
    #expect(encoded.control >> 5 & 0xff == 0x0f)
  }

  @Test
  internal func watchpoint() throws {
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x1003), size: 2,
                       kind: .watchpoint(.readwrite))
    let encoded = try ARM64BreakpointControl.encode(site)
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
      try ARM64BreakpointControl.encode(site)
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
    let encoded = try ARM64BreakpointControl.encode(site)
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
  internal func breakpoint() throws {
    let site =
        BreakpointSite(address: Debuggee.Address(rawValue: 0x1000), size: 1,
                       kind: .hardware)
    let encoded = try X86BreakpointControl.encode(site)
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
    let encoded = try X86BreakpointControl.encode(site)
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
      try X86BreakpointControl.encode(site)
    }
  }
}
#endif

#if os(anyAppleOS)
internal import Darwin

@Suite
internal struct DarwinDebugControlTests {
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
    #expect(DarwinError.task(KERN_FAILURE, invalid: .process) == .access)
  }

  @Test
  internal func attach() throws {
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
    } else {
      Issue.record("attach did not report a stop")
    }
    try control.detach(process, stopped: false)
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
