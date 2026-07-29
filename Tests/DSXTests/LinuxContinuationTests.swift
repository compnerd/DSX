// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Linux)
internal import Glibc
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxContinuationTests {
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
  }
}
#endif
