// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct UnixWaitStatusTests {
  @Test(arguments: [CInt(0), 1, 5, 19, 255])
  internal func stopped(_ signal: CInt) {
#if os(anyAppleOS)
    // Darwin reserves this encoding for WIFCONTINUED, not a stop signal.
    if signal == 19 {
      return
    }
#endif
    let status = UnixWaitStatus(stopped: signal)
    #expect(status.stopped)
    #expect(status.signal == signal)
    #expect(status.exit == nil)
    #expect(status.rawValue == 0x7f | signal << 8)
  }

  @Test
  internal func terminal() {
    #expect(UnixWaitStatus(42 << 8).exit == .exited(42))
    #expect(UnixWaitStatus(9).exit == .signalled(9))
    #expect(UnixWaitStatus(0x89).exit == .signalled(9))
    #expect(UnixWaitStatus(0xffff).exit == nil)
#if os(anyAppleOS) || os(FreeBSD)
    #expect(UnixWaitStatus(0xffff).stopped)
#else
    #expect(UnixWaitStatus(0xffff).stopped == false)
#endif
  }

  @Test
  internal func continued() {
#if os(anyAppleOS)
    let status = UnixWaitStatus(0x137f)
#elseif os(FreeBSD)
    let status = UnixWaitStatus(0x13)
#else
    let status = UnixWaitStatus(0xffff)
#endif
    #expect(status.continued)
    #expect(status.stopped == false)
    #expect(status.exit == nil)
  }
}
