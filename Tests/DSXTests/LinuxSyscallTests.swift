// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxSyscallTests {
  @Test
  internal func exiting() throws {
#if os(Android)
    let executable = "/system/bin/sleep"
#else
    let executable = "/bin/sleep"
#endif
    var arguments = [strdup(executable), strdup("30"), nil]
    defer {
      free(arguments[0])
      free(arguments[1])
    }
    var child: pid_t = 0
    try #require(posix_spawn(&child, executable, nil, nil, &arguments,
                             environ) == 0)
    defer {
      _ = DSX::kill(child, SIGKILL)
      _ = waitpid(child, nil, 0)
    }
    let process = ProcessIdentifier(rawValue: UInt64(child))
    var control = LinuxDebugControl()
    try control.attach(process)
    defer { try? control.close() }
    guard case .stopped = try control.event() else {
      Issue.record("attachment did not report a stop")
      return
    }
    try #require(DSX::kill(child, SIGKILL) == 0)
    #expect(try control.event(blocking: true) == nil)
    #expect(control.threads[child]?.exiting == true)
    guard case .exited(let identifier, _) =
        try control.event(blocking: true) else {
      Issue.record("exiting thread lost its final status")
      return
    }
    #expect(identifier == process)
    #expect(control.threads.isEmpty)
  }

#if arch(x86_64) || arch(i386)
  @Test(arguments: [UInt64(0x1000), 0x2000])
  internal func redirection(_ address: UInt64) {
    var registers = LinuxGeneralRegisters()
    registers.origin = 35
    registers.program = 0x1000
    let saved = registers
    registers.set(pc: address)
    #expect(registers.program == address)
    #expect(registers.origin == .max)
    #expect(saved.origin == 35)
    #expect(saved.program == 0x1000)
  }
#endif

#if arch(x86_64) || arch(arm64)
  @Test(arguments: [false, true])
  internal func injection(_ blocked: Bool) throws {
#if os(Android)
    let executable = "/system/bin/sleep"
#else
    let executable = "/bin/sleep"
#endif
    var arguments = [strdup(executable), strdup("30"), nil]
    defer {
      free(arguments[0])
      free(arguments[1])
    }
    var mask = sigset_t()
    sigemptyset(&mask)
    if blocked {
      sigaddset(&mask, SIGTRAP)
    }
    var previous = sigset_t()
    try #require(pthread_sigmask(SIG_SETMASK, &mask, &previous) == 0)
    var child: pid_t = 0
    let status = posix_spawn(&child, executable, nil, nil, &arguments, environ)
    let restored = pthread_sigmask(SIG_SETMASK, &previous, nil)
    try #require(status == 0)
    defer {
      _ = DSX::kill(child, SIGKILL)
      _ = waitpid(child, nil, 0)
    }
    try #require(restored == 0)
    let process = ProcessIdentifier(rawValue: UInt64(child))
    var control = LinuxDebugControl()
    try control.attach(process)
    defer { try? control.close() }
    guard case .stopped(let stop) = try control.event() else {
      Issue.record("attachment did not report a stop")
      return
    }
    var session = DebugSession()
#if arch(x86_64)
    let origin = try LinuxRegisterState(stop.thread).general.origin
#endif
    let saved = try session.save(stop.thread)
    var registers = try NativeRegisterState(stop.thread)
    try registers.set(pc: registers.pc)
    try registers.commit(stop.thread)
#if arch(x86_64)
    #expect(try LinuxRegisterState(stop.thread).general.origin == UInt64.max)
#endif
    try session.restore(saved, thread: nil)
    #expect(session.snapshots.isEmpty)
#if arch(x86_64)
    #expect(try LinuxRegisterState(stop.thread).general.origin == origin)
#endif
    let address =
        try LinuxMemory.allocate(process, size: 4096, readable: true,
                                 writable: true, executable: false,
                                 control: &control)
    try LinuxMemory.deallocate(process, address: address, size: 4096,
                               control: &control)
    try #require(DSX::kill(child, SIGUSR1) == 0)
    #expect(throws: Debuggee.Error.state) {
      try LinuxMemory.allocate(process, size: 4096, readable: true,
                               writable: true, executable: false,
                               control: &control)
    }
    guard case .stopped(let stop) = try control.event() else {
      Issue.record("injected syscall lost the pending signal")
      return
    }
    #expect(stop.reason == .signal(SIGUSR1))
    #expect(stop.thread.process == process)
  }
#endif

  @Test
  internal func pending() throws(Debuggee.Error) {
    var control = LinuxDebugControl()
    control.status = 0
    control.thread = 100
    let actions = Array<Debuggee.Continuation>()
    try control.resume(actions.span)
    #expect(control.status == 0)
    #expect(control.thread == 100)
  }

  @Test
  internal func deferral() throws(Debuggee.Error) {
    let process = ProcessIdentifier(rawValue: 100)
    var information = siginfo_t()
    information.si_signo = SIGCHLD
    var control = LinuxDebugControl()
    control.process = process
    control.threads = [
      100: LinuxThreadState(process: process, stopped: true,
                            signal: information),
    ]
    let actions = [Debuggee.Continuation(selection: .all, operation: .resume)]
    try control.resume(actions.span)
    #expect(control.status == UnixWaitStatus(stopped: SIGCHLD).rawValue)
    #expect(control.thread == 100)
    #expect(control.threads[100]?.stopped == true)
    #expect(control.threads[100]?.reported == true)
  }

  @Test
  internal func ownership() throws(Debuggee.Error) {
    let parent = ProcessIdentifier(rawValue: 100)
    let child = ProcessIdentifier(rawValue: 200)
    var control = LinuxDebugControl()
    control.process = parent
    control.children.insert(200)
    control.threads = [
      100: LinuxThreadState(process: parent),
      101: LinuxThreadState(process: parent, stopped: true),
      200: LinuxThreadState(process: child, stopped: true),
      201: LinuxThreadState(process: child, stopped: true),
      202: LinuxThreadState(process: child, stopped: true),
    ]
    #expect(try control.thread(parent) == 101)
    #expect(try control.thread(child) == 200)
    control.threads[200]?.stopped = false
    #expect(try control.thread(child) == 201)
    control.threads[101]?.stopped = false
    #expect(throws: Debuggee.Error.state) {
      try control.thread(parent)
    }
    #expect(throws: Debuggee.Error.process) {
      try control.thread(ProcessIdentifier(rawValue: 300))
    }
  }

  @Test(arguments: [UInt32(0x7fff_ffff), 0x8000_0000, 0xb000_0000, 0xffff_f000])
  internal func addresses(_ value: UInt32) throws(Debuggee.Error) {
    let registers = result(UInt64(value))
    #expect(try registers.result == UInt64(value))
  }

  @Test(arguments: [UInt64(1), 4095])
  internal func errors(_ code: UInt64) {
    #expect(throws: Debuggee.Error.self) {
      try result(0 &- code).result
    }
  }

  private func result(_ value: UInt64) -> LinuxGeneralRegisters {
    var registers = LinuxGeneralRegisters()
#if arch(arm)
    registers.values[0] = UInt32(truncatingIfNeeded: value)
#elseif arch(arm64)
    registers.values[0] = value
#elseif arch(i386)
    registers.eax = UInt32(truncatingIfNeeded: value)
#elseif arch(x86_64)
    registers.rax = value
#endif
    return registers
  }
}
#endif
