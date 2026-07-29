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
    let trap = try information.trap(pc: 0x1001, fallback: .trace)
    #expect(trap.address == address)
    #expect(trap.reason == .breakpoint)

    information.si_code = TRAP_TRACE
    let step = try information.trap(pc: 0x1001, fallback: .signal(SIGTRAP))
    #expect(step.address == 0x1001)
    #expect(step.reason == .trace)

    information.si_code = SI_TKILL
    let raised = try information.trap(pc: 0x1001, fallback: .trace)
    #expect(raised.address == 0x1001)
    #expect(raised.reason == .signal(SIGTRAP))

    information.si_code = SI_USER
    let fallback =
        try information.trap(pc: 0x1001, fallback: .signal(SIGTRAP),
                             stepping: true)
    #expect(fallback.address == 0x1001)
    #expect(fallback.reason == .trace)

    information.si_code = TRAP_BRKPT
    let interrupted =
        try information.trap(pc: 0x1001, fallback: .trace, stepping: true)
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
    #expect(information.address(for: SIGSEGV) == nil)
    information.si_code = TRAP_TRACE
    #expect(information.generated(by: 0) == false)
    information.si_code = SEGV_MAPERR
    #expect(information.address(for: SIGSEGV) == 0)
    #expect(information.address(for: SIGTRAP) == nil)
    information.si_code = BUS_ADRALN
    #expect(information.address(for: SIGBUS) == 0)
    information.si_code = SI_KERNEL
    #expect(information.address(for: SIGSEGV) == 0)
    #expect(information.address(for: SIGBUS) == nil)
    for code in [DSX::BUS_MCEERR_AR, DSX::BUS_MCEERR_AO] {
      information.si_code = code
      #expect(information.address(for: SIGBUS) == 0)
    }
    for code in [DSX::SEGV_MTEAERR, DSX::SEGV_MTESERR, DSX::SEGV_CPERR] {
      information.si_code = code
      #expect(information.address(for: SIGSEGV) == 0)
    }
    information.si_code = TRAP_HWBKPT
    let trap = try information.trap(pc: 0x1004, fallback: .trace)
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
#if os(Windows) && (arch(i386) || arch(x86_64))
    #expect(HardwareBreakpoint.advance(.hardware) == false)
#else
    #expect(HardwareBreakpoint.advance(.hardware)
        == HardwareBreakpoint.supports(.hardware))
#endif
    #expect(HardwareBreakpoint.advance(.software) == false)
#if os(Windows) && arch(arm64)
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

  @Test(arguments: Array(0 ..< 16) + [X86BreakpointControl.Word.max])
  internal func acknowledgement(_ status: X86BreakpointControl.Word) {
    for slot in 0 ..< 4 {
      let expected = status & ~(1 << slot)
      #expect(X86BreakpointControl.acknowledge(status, slot: slot) == expected)
    }
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

  @Test(arguments: [false, true], [CInt(0), SIGCONT, SIGUSR1, SIGKILL])
  internal func attach(_ stopped: Bool, signal: CInt) throws {
    // Fork our entitled image instead of attaching to a protected executable.
    // The child calls only async-signal-safe functions before being killed.
    var mask = sigset_t()
    try #require(sigemptyset(&mask) == 0)
    let child = DSX::fork()
    if child == 0 {
      _ = sigprocmask(SIG_SETMASK, &mask, nil)
      while true {
        pause()
      }
    }
    try #require(child > 0)
    var control = DarwinDebugControl()
    defer { control.reap(child) }
    let process = ProcessIdentifier(rawValue: UInt64(child))
    try control.attach(process)
    let deadline = try Deadline(seconds: 10, now: Host.time)
    if case .stopped(let stop) = try control.event(until: deadline) {
      #expect(stop.thread.process == process)
      let action =
          Debuggee.Continuation(selection: .thread(stop.thread),
                                operation: .resume, signal: signal)
      let actions: InlineArray<1, Debuggee.Continuation> = [action]
      try control.resume(actions.span)
      if signal == SIGUSR1 || signal == SIGKILL {
        guard case .exited(let exited, .signalled(let delivered)) =
            try control.event(until: deadline) else {
          Issue.record("thread-directed signal did not terminate the child")
          return
        }
        #expect(exited == process)
        #expect(delivered == signal)
        return
      }
      try control.interrupt(process)
      guard case .stopped(let interrupted) =
          try control.event(until: deadline) else {
        Issue.record("interrupt did not report a stop")
        return
      }
      #expect(interrupted.thread.process == process)
      #expect(interrupted.reason == .interrupt)
    } else {
      Issue.record("attach did not report a stop")
    }
    let task = try DarwinTask(process)
    try control.detach(process, stopped: stopped)
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let count = proc_pidinfo(child, PROC_PIDTBSDINFO, 0, &info, size)
    try #require(count == size)
    #expect(info.pbi_status == (stopped ? SSTOP : SRUN))
    #expect(try task.suspension == (stopped ? 1 : 0))
  }

  internal enum Disposition: CaseIterable, Sendable {
    case terminate, exit, notify
  }

  @Test(arguments: [(false, false), (false, true), (true, false), (true, true)],
        [SIGSTOP, SIGCONT])
  internal func pending(_ fixture: (Bool, Bool), signal: CInt) throws {
    let (stopped, suspended) = fixture
    var descriptors = Array(repeating: CInt(-1), count: 2)
    try #require(socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0)
    let parent = descriptors[0]
    let peer = descriptors[1]
    defer { _ = DSX::close(parent) }
    let child = DSX::fork()
    if child == 0 {
      _ = DSX::close(parent)
      var byte: UInt8 = 0
      while true {
        let count = DSX::read(peer, &byte, 1)
        if count < 0, errno == EINTR {
          continue
        }
        if count == 1 {
          _ = DSX::write(peer, &byte, 1)
        }
        break
      }
      while true {
        pause()
      }
    }
    _ = DSX::close(peer)
    try #require(child > 0)
    var control = DarwinDebugControl()
    defer { control.reap(child) }
    let process = ProcessIdentifier(rawValue: UInt64(child))
    try control.attach(process)
    let deadline = try Deadline(seconds: 10, now: Host.time)
    guard case .stopped = try control.event(until: deadline) else {
      Issue.record("attach did not report a stop")
      return
    }
    // The current Mach exception has consumed its SIGSTOP. A further signal
    // remains pending in BSD and is independent of PT_DETACH's reply signal.
    try #require(DSX::kill(child, signal) == 0)
    let task = try DarwinTask(process)
    let threads = try DarwinThreadList(process, control: control)
    try #require(threads.count > 0)
    let thread = threads[0]
    if suspended {
      try #require(thread_suspend(thread) == KERN_SUCCESS)
      do throws(Debuggee.Error) {
        var snapshot = try DarwinThreadList(process, control: control)
        try snapshot.suspend()
        try snapshot.suspend()
        // Acquiring twice is idempotent, and unwinding releases only the
        // snapshot's hold. The independently acquired hold must survive.
        throw .state
      } catch {
        #expect(error == .state)
      }
    }
    try control.detach(process, stopped: stopped)
    #expect(control.process == nil)
    #expect(control.held.isEmpty)
    if suspended {
      // Detach must release DSX's holds, not a suspension owned by someone
      // else. Verify the native count before allowing the child to proceed.
      var basic = thread_basic_info_data_t()
      let bytes = MemoryLayout.size(ofValue: basic)
      let capacity = bytes / MemoryLayout<integer_t>.size
      var count = mach_msg_type_number_t(capacity)
      let status = withUnsafeMutablePointer(to: &basic) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) {
          thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
        }
      }
      try #require(status == KERN_SUCCESS)
      #expect(basic.suspend_count == 1)
      try #require(thread_resume(thread) == KERN_SUCCESS)
    }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    let count = proc_pidinfo(child, PROC_PIDTBSDINFO, 0, &info, size)
    try #require(count == size)
    #expect(info.pbi_status == (stopped ? SSTOP : SRUN))
    #expect(try task.suspension == (stopped ? 1 : 0))
    if stopped {
      try #require(DSX::kill(child, SIGCONT) == 0)
    }
    // Verify actual execution, not just a transient SRUN before a queued stop
    // takes effect. The detached child must service a fresh request.
    var byte: UInt8 = 1
    try #require(DSX::write(parent, &byte, 1) == 1)
    var descriptor = pollfd(fd: parent, events: Int16(POLLIN), revents: 0)
    try #require(poll(&descriptor, 1, 10_000) == 1)
    byte = 0
    try #require(DSX::read(parent, &byte, 1) == 1)
    #expect(byte == 1)
  }

  @Test(arguments: [(Disposition.terminate, SIGUSR1), (.exit, SIGUSR1),
                    (.notify, SIGUSR1), (.notify, SIGCONT)],
        [SIGSTOP, SIGUSR2])
  internal func signal(_ delivery: (Disposition, CInt), original: CInt) throws {
    let (disposition, signal) = delivery
    var descriptors = Array(repeating: CInt(-1), count: 2)
    try #require(pipe(&descriptors) == 0)
    let input = descriptors[0]
    let output = descriptors[1]
    defer { _ = DSX::close(input) }
    var mask = sigset_t()
    try #require(sigemptyset(&mask) == 0)
    var action = sigaction()
    action.__sigaction_u.__sa_handler = switch disposition {
    case .terminate: SIG_DFL
    case .exit: { signal in DSX::_exit(signal) }
    case .notify: { signal in
      var byte = UInt8(signal)
      _ = DSX::write(STDOUT_FILENO, &byte, 1)
    }
    }
    let child = DSX::fork()
    if child == 0 {
      _ = DSX::close(input)
      _ = dup2(output, STDOUT_FILENO)
      _ = sigaction(signal, &action, nil)
      _ = sigprocmask(SIG_SETMASK, &mask, nil)
      var ready: UInt8 = 1
      _ = DSX::write(output, &ready, 1)
      _ = DSX::close(output)
      while true {
        pause()
      }
    }
    _ = DSX::close(output)
    try #require(child > 0)
    var control = DarwinDebugControl()
    defer { control.reap(child) }
    var descriptor = pollfd(fd: input, events: Int16(POLLIN), revents: 0)
    try #require(poll(&descriptor, 1, 10_000) == 1)
    var ready: UInt8 = 0
    try #require(DSX::read(input, &ready, 1) == 1 && ready == 1)
    let process = ProcessIdentifier(rawValue: UInt64(child))
    try control.attach(process)
    let deadline = try Deadline(seconds: 10, now: Host.time)
    guard case .stopped(let initial) = try control.event(until: deadline) else {
      Issue.record("attach did not report a stop")
      return
    }
    let resume: InlineArray<1, Debuggee.Continuation> = [
      Debuggee.Continuation(selection: .thread(initial.thread),
                            operation: .resume),
    ]
    if original == SIGUSR2 {
      try control.resume(resume.span)
      try #require(DSX::kill(child, original) == 0)
      guard case .stopped(let stop) = try control.event(until: deadline) else {
        Issue.record("signal did not report a stop")
        return
      }
      try #require(stop.reason == .signal(original))
    }
    let actions: InlineArray<1, Debuggee.Continuation> = [
      Debuggee.Continuation(selection: .thread(initial.thread),
                            operation: .resume, signal: signal),
    ]
    try control.resume(actions.span)
    if disposition == .notify {
      while true {
        guard case nil = try control.event(output: false) else {
          Issue.record("replacement signal was exposed as a client stop")
          return
        }
        if poll(&descriptor, 1, 0) > 0 {
          break
        }
        try #require(deadline.remaining(at: Host.time) > 0)
        usleep(1_000)
      }
      var delivered: UInt8 = 0
      try #require(DSX::read(input, &delivered, 1) == 1)
      #expect(delivered == signal)
      // Only the requested delivery is internal. A subsequent external
      // instance of the same signal must still be reported to the client.
      try #require(DSX::kill(child, signal) == 0)
      guard case .stopped(let stop) = try control.event(until: deadline) else {
        Issue.record("external signal was swallowed after replacement")
        return
      }
      #expect(stop.reason == .signal(signal))
      return
    }
    guard case .exited(let exited, let status) =
        try control.event(until: deadline) else {
      Issue.record("replacement signal required another client resume")
      return
    }
    #expect(exited == process)
    let expected: Debuggee.Exit = disposition == .exit
        ? .exited(signal) : .signalled(signal)
    #expect(status == expected)
  }

  @Test(arguments: [false, true])
  internal func launch(_ pending: Bool) throws {
    let current = ProcessIdentifier(rawValue: UInt64(getpid()))
    let image = try current.image
    let executable = try #require(image).path
    var control = DarwinDebugControl()
    let config = Debuggee.Launch(executable: executable)
    let process = try control.launch(config)
    let identifier = try process.native
    defer { control.reap(identifier) }
    let deadline = try Deadline(seconds: 10, now: Host.time)
    guard case .stopped(let stop) = try control.event(until: deadline) else {
      Issue.record("launch did not report its initial stop")
      return
    }
    #expect(stop.thread.process == process)
    #expect(stop.reason == .signal(SIGSTOP))
    let task = try control.task(process)
    #expect(try control.task(process) === task)
    let other = ProcessIdentifier(rawValue: UInt64(getpid()))
    #expect(throws: Debuggee.Error.process) {
      _ = try control.task(other)
    }
    let threads = try DarwinThreadList(process, control: control)
    #expect(threads.count > 0)
    if pending {
      // Consume the BSD stop so it cannot satisfy the later exit wait.
      var status: CInt = 0
      let result = waitpid(identifier, &status, WNOHANG)
      try #require(result == 0 || result == identifier)
      if result == identifier {
        try #require(UnixWaitStatus(status).stopped)
      }
      try #require(DSX::kill(identifier, SIGKILL) == 0)
      control.discard()
    } else {
      try control.terminate(process)
    }
    guard case .exited(let exited, .signalled(SIGKILL)) =
        try control.event(until: deadline) else {
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

extension DarwinDebugControl {
  fileprivate mutating func reap(_ process: pid_t) {
    _ = DSX::kill(process, SIGKILL)
    // A pending Mach exception can keep a killed child from exiting.
    // Release replies and owned suspensions before waiting for its exit.
    discard()
    while true {
      var status: CInt = 0
      switch waitpid(process, &status, 0) {
      case process:
        if UnixWaitStatus(status).stopped {
          continue
        }
      case -1 where errno == EINTR:
        continue
      default:
        break
      }
      return
    }
  }

  // Bound native event waits so failures reach cleanup rather than hanging
  // the test executable until CTest's suite-wide timeout.
  fileprivate mutating func event(until deadline: Deadline)
      throws(Debuggee.Error) -> Debuggee.Event {
    while true {
      if let event = try event(output: false) {
        return event
      }
      guard try deadline.remaining(at: Host.time) > 0 else {
        throw .system(ETIMEDOUT)
      }
      usleep(1_000)
    }
  }
}
#endif
