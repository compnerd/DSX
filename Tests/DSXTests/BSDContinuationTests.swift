// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc
internal import Testing
@testable internal import DSX

@Suite
internal struct BSDContinuationTests {
  @Test
  internal func failure() throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let status = UnixWaitStatus(stopped: SIGUSR1).rawValue
    var control = BSDDebugControl()
    control.process = process
    control.status = status
    control.request = DSX::PT_CONTINUE
    var signals = SignalSet()
    signals.insert(UInt8(SIGUSR1))
    for _ in 0 ..< 2 {
      do {
        _ = try control.event(signals: signals)
        Issue.record("resumed a process that was not traced")
      } catch {
        #expect(control.status == status)
        #expect(control.request == DSX::PT_CONTINUE)
      }
    }
  }
}
#endif
