// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct NativeAddressTests {
  @Test(arguments: [UInt64(0), 0x7fff_ffff, 0x8000_0000, 0xffff_ffff])
  internal func representable(_ value: UInt64) throws(Debuggee.Error) {
    #expect(try Debuggee.Address(rawValue: value).native == UInt(value))
  }

  @Test(arguments: [UInt64(0x1_0000_0000), UInt64.max])
  internal func width(_ value: UInt64) throws(Debuggee.Error) {
    let address = Debuggee.Address(rawValue: value)
    if UInt.bitWidth == 32 {
      #expect(throws: Debuggee.Error.memory) { try address.native }
    } else {
      #expect(try address.native == UInt(value))
    }
  }
}
