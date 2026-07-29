// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct SignalSetTests {
  @Test
  internal func boundaries() {
    var signals = SignalSet()
    for signal: UInt8 in [0, 63, 64, 127, 128, 191, 192, 255] {
      #expect(signals.contains(CInt(signal)) == false)
      signals.insert(signal)
      #expect(signals.contains(CInt(signal)))
    }
    #expect(signals.contains(-1) == false)
    #expect(signals.contains(256) == false)
    #expect(signals.contains(1) == false)
  }
}
