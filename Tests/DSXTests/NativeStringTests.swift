// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct NativeStringTests {
#if os(Windows)
  private typealias Unit = UInt16
#else
  private typealias Unit = UInt8
#endif

  @Test
  internal func bounded() {
    let value = (Unit(65), Unit(66))
    #expect(withUnsafeBytes(of: value) { String(native: $0) } == "AB")
    #expect(value.0 == 65 && value.1 == 66)
  }

  @Test
  internal func terminated() {
    let value = (Unit(65), Unit(0), Unit(66))
    #expect(withUnsafeBytes(of: value) { String(native: $0) } == "A")
    #expect(withUnsafeBytes(of: Unit(0)) { String(native: $0) }.isEmpty)
  }

  @Test
  internal func unicode() {
#if os(Windows)
    let value = (UInt16(0xd83d), UInt16(0xde00), UInt16(0))
#else
    let value = (UInt8(0xf0), UInt8(0x9f), UInt8(0x98), UInt8(0x80), UInt8(0))
#endif
    #expect(withUnsafeBytes(of: value) { String(native: $0) } == "\u{1f600}")
  }
}
