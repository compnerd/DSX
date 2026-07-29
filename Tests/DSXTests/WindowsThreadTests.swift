// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsThreadTests {
  @Test
  internal func tib() throws(Debuggee.Error) {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let thread = ThreadIdentifier(rawValue: UInt64(GetCurrentThreadId()))
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    let address = try identifier.tib
    #expect(address.rawValue > 0)
  }
}
#endif
