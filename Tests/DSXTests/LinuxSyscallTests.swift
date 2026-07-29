// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxSyscallTests {
  @Test(arguments: [UInt32(0x7fff_ffff), 0x8000_0000, 0xb000_0000, 0xffff_f000])
  internal func addresses(_ value: UInt32) throws(Debuggee.Error) {
    let raw = if UInt.bitWidth == 32 {
      UInt64(bitPattern: Int64(Int32(bitPattern: value)))
    } else {
      UInt64(value)
    }
    #expect(try LinuxDebugControl.validate(raw) == UInt64(value))
  }

  @Test(arguments: [UInt64(1), 4095])
  internal func errors(_ code: UInt64) {
    #expect(throws: Debuggee.Error.self) {
      try LinuxDebugControl.validate(0 &- code)
    }
  }
}
#endif
