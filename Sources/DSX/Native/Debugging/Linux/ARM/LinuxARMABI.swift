// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm)
extension ABI {
  internal static func breakpoint(_ program: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    program
  }

  internal static var map: UInt64 { 192 }
  internal static var unmap: UInt64 { 91 }
  internal static var word: Int { 4 }

  internal static func instruction(_ registers: borrowing LinuxGeneralRegisters,
                                   into bytes: inout InlineArray<4, UInt8>)
      -> Int {
    if registers.values[16] & 0x20 != 0 {
      bytes[0] = 0x00
      bytes[1] = 0xdf
      return 2
    }
    bytes[0] = 0x00
    bytes[1] = 0x00
    bytes[2] = 0x00
    bytes[3] = 0xef
    return 4
  }

  internal static func prepare(_ arguments: borrowing Span<UInt64>,
                               registers: inout LinuxGeneralRegisters)
      throws(Debuggee.Error) {
    guard arguments.count > 0, arguments.count <= 7 else {
      throw .state
    }
    registers.values[7] = UInt32(truncatingIfNeeded: arguments[0])
    for index in 1 ..< arguments.count {
      registers.values[index - 1] = UInt32(truncatingIfNeeded: arguments[index])
    }
  }

  internal static func program(_ address: UInt64,
                               registers: inout LinuxGeneralRegisters) {
    registers.values[15] = UInt32(truncatingIfNeeded: address)
  }

  internal static func program(_ registers: borrowing LinuxGeneralRegisters)
      -> UInt64 {
    UInt64(registers.values[15])
  }

  internal static func result(_ registers: borrowing LinuxGeneralRegisters)
      -> UInt64 {
    UInt64(bitPattern: Int64(Int32(bitPattern: registers.values[0])))
  }
}
#endif
