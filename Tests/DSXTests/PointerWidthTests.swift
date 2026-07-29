// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct PointerWidthTests {
  @Test(arguments: [(PointerWidth.b32, 4), (.b64, 8), (.b128, 16)])
  internal func sizes(_ fixture: (PointerWidth, Int)) {
    let (width, bytes) = fixture
    #expect(width.bytes == bytes)
    #expect(width.rawValue == bytes * 8)
  }

  @Test
  internal func unsupported() {
    #expect(PointerWidth(rawValue: 16) == nil)
    #expect(PointerWidth(rawValue: 0) == nil)
  }
}
