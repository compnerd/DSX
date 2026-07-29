// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Linux)
internal import Glibc
internal import DSXTestSupport
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxContinuationTests {
  @Test(arguments: [false, true], [CInt(0), SIGUSR1])
  internal func death(_ notification: Bool, _ delivery: CInt) throws {
    let child = Glibc.fork()
    if child == 0 {
      if DSX::ptrace(DSX::PTRACE_TRACEME, 0, nil, nil) < 0 {
        Glibc._exit(1)
      }
      _ = raise(SIGSTOP)
      Glibc._exit(2)
    }
    try #require(child > 0)
    defer {
      _ = kill(child, SIGKILL)
      _ = waitpid(child, nil, 0)
    }
    var status: CInt = 0
    try #require(waitpid(child, &status, 0) == child)
    try #require(UnixWaitStatus(status).stopped)
    let process = ProcessIdentifier(rawValue: UInt64(child))
    let thread = ThreadIdentifier(rawValue: UInt64(child))
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    var control = LinuxDebugControl()
    var signal = siginfo_t()
    signal.si_signo = SIGUSR1
    control.process = process
    control.configured = true
    control.threads[child] =
        LinuxThreadState(process: process, stopped: true, signal: signal)
    try #require(kill(child, SIGKILL) == 0)
    // Observe death without consuming the status owned by the event source.
    var information = siginfo_t()
    try #require(waitid(P_PID, id_t(child), &information,
                        WEXITED | WNOWAIT) == 0)
    if notification {
      try control.discard(.started(identifier))
    } else {
      try control.resume(child, request: DSX::PTRACE_CONT, signal: delivery)
    }
    #expect(control.threads[child]?.stopped == false)
    #expect(control.threads[child]?.exiting == true)
    #expect(control.threads[child]?.stepping == false)
    guard case let .exited(owner, status) =
        try control.event(output: false) else {
      Issue.record("restart lost the terminal status")
      return
    }
    #expect(owner == process)
    #expect(status == .signalled(SIGKILL))
    #expect(control.process == nil)
  }

  @Test(arguments: [SIGSTOP, SIGTRAP, SIGSEGV])
  internal func collection(_ signal: CInt) throws {
    let child = Glibc.fork()
    if child == 0 {
      if DSX::ptrace(DSX::PTRACE_TRACEME, 0, nil, nil) < 0 {
        Glibc._exit(1)
      }
      _ = raise(signal)
      Glibc._exit(47)
    }
    try #require(child > 0)
    defer {
      _ = kill(child, SIGKILL)
      _ = waitpid(child, nil, 0)
    }
    var status: CInt = 0
    try #require(waitpid(child, &status, 0) == child)
    try #require(UnixWaitStatus(status).stopped)
    let process = ProcessIdentifier(rawValue: UInt64(child))
    var control = LinuxDebugControl()
    control.process = process
    control.configured = true
    control.status = status
    control.thread = child
    control.threads[child] = LinuxThreadState(process: process)
    // A collected stop can become obsolete before its siginfo is read.
    try #require(kill(child, SIGKILL) == 0)
    var information = siginfo_t()
    try #require(waitid(P_PID, id_t(child), &information,
                        WEXITED | WNOWAIT) == 0)
    guard case let .exited(owner, exit) =
        try control.event(output: false) else {
      Issue.record("collected stop lost the terminal status")
      return
    }
    #expect(owner == process)
    #expect(exit == .signalled(SIGKILL))
    #expect(control.process == nil)
  }

  @Test("Retain a killed group leader until its siblings exit")
  internal func group() throws {
    let child = Glibc.fork()
    if child == 0 {
      if DSX::ptrace(DSX::PTRACE_TRACEME, 0, nil, nil) < 0 {
        Glibc._exit(1)
      }
      _ = raise(SIGSTOP)
      var thread = pthread_t()
      if pthread_create(&thread, nil, { _ in
        while true {
          _ = pause()
        }
      }, nil) == 0 {
        dsx_test_exit_thread(47)
      }
      Glibc._exit(2)
    }
    try #require(child > 0)
    var sibling: pid_t?
    defer {
      _ = kill(child, SIGKILL)
      for native in [sibling, child].compactMap({ $0 }) {
        _ = DSX::ptrace(DSX::PTRACE_CONT, native, nil, nil)
        var status: CInt = 0
        while waitpid(native, &status, DSX::__WALL) == native {
          if UnixWaitStatus(status).stopped {
            _ = DSX::ptrace(DSX::PTRACE_CONT, native, nil, nil)
          }
        }
      }
    }
    var status: CInt = 0
    try #require(waitpid(child, &status, 0) == child)
    try #require(UnixWaitStatus(status).stopped)
    try LinuxDebugControl.configure(child)
    try #require(DSX::ptrace(DSX::PTRACE_CONT, child, nil, nil) == 0)
    try #require(waitpid(child, &status, DSX::__WALL) == child)
    try #require(status >> 16 == DSX::PTRACE_EVENT_CLONE)
    var message: UInt = 0
    try #require(DSX::ptrace(DSX::PTRACE_GETEVENTMSG, child, nil, &message) == 0)
    let thread = pid_t(message)
    sibling = thread
    try #require(waitpid(thread, &status, DSX::__WALL) == thread)
    try #require(DSX::ptrace(DSX::PTRACE_CONT, thread, nil, nil) == 0)
    try #require(DSX::ptrace(DSX::PTRACE_CONT, child, nil, nil) == 0)
    try #require(waitpid(child, &status, DSX::__WALL) == child)
    try #require(status >> 16 == DSX::PTRACE_EVENT_EXIT)
    let process = ProcessIdentifier(rawValue: UInt64(child))
    var control = LinuxDebugControl()
    control.process = process
    control.configured = true
    control.status = status
    control.thread = child
    control.threads[child] = LinuxThreadState(process: process)
    control.threads[thread] = LinuxThreadState(process: process)
    // SIGKILL destroys the leader's collected exit stop. Its final status
    // cannot become waitable while the sibling remains in its exit stop.
    try #require(kill(child, SIGKILL) == 0)
    try #require(waitpid(thread, &status, DSX::__WALL) == thread)
    try #require(status >> 16 == DSX::PTRACE_EVENT_EXIT)
    control.threads[thread]?.pending = status
    #expect(try control.event(blocking: true, output: false) == nil)
    #expect(control.threads[child]?.exiting == true)
    var result: Debuggee.Exit?
    while result == nil {
      if case let .exited(owner, exit) =
          try control.event(blocking: true, output: false) {
        #expect(owner == process)
        result = exit
      }
    }
    #expect(result == .signalled(SIGKILL))
    #expect(control.process == nil)
    #expect(control.threads.isEmpty)
    sibling = nil
  }

  @Test
  internal func failure() throws {
    let native = getpid()
    let process = ProcessIdentifier(rawValue: UInt64(native))
    var control = LinuxDebugControl()
    var signal = siginfo_t()
    signal.si_signo = SIGUSR1
    control.threads[native] =
        LinuxThreadState(process: process, stopped: true, signal: signal,
                         reported: true)
    // This process is not its own tracee. Both preparation and restart fail.
    for delivery in [SIGUSR1, 0] {
      do {
        try control.resume(native, request: DSX::PTRACE_CONT, signal: delivery)
        Issue.record("resumed a process that was not traced")
      } catch {
        #expect(control.threads[native]?.signal?.si_signo == SIGUSR1)
        #expect(control.threads[native]?.reported == true)
        #expect(control.threads[native]?.stopped == true)
        #expect(control.threads[native]?.stepping == false)
      }
    }
    control.process = process
    control.configured = true
    control.status = (SIGSTOP << 8) | 0x7f
    control.thread = native
    do {
      _ = try control.event(output: false)
      Issue.record("discarded a stop without a terminal status")
    } catch {
      #expect(control.status == (SIGSTOP << 8) | 0x7f)
      #expect(control.thread == native)
      #expect(control.process == process)
    }
  }
}
#endif
