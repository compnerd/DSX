// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import Testing
@testable internal import DSX

@Suite internal struct DarwinEventTests {
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
    guard case .exited(let identifier, _) = event else {
      Issue.record("The reaped exit must remain available after a read failure")
      return
    }
    #expect(identifier == process)
    #expect(control.process == nil)
    #expect(control.deferred == nil)
  }
}
#endif
