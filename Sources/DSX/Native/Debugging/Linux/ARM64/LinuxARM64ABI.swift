// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
extension ABI {
  internal static func breakpoint(_ program: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    program
  }

  internal static var map: UInt64 { 222 }
  internal static var unmap: UInt64 { 215 }
  internal static var word: Int { 8 }

  internal static func instruction(_: borrowing LinuxGeneralRegisters,
                                   into bytes: inout InlineArray<4, UInt8>)
      -> Int {
    bytes[0] = 0x01
    bytes[1] = 0x00
    bytes[2] = 0x00
    bytes[3] = 0xd4
    return 4
  }

  internal static func prepare(_ arguments: borrowing Span<UInt64>,
                               registers: inout LinuxGeneralRegisters)
      throws(Debuggee.Error) {
    guard arguments.count > 0, arguments.count <= 7 else {
      throw .state
    }
    registers.values[8] = arguments[0]
    for index in 1 ..< arguments.count {
      registers.values[index - 1] = arguments[index]
    }
  }

  internal static func program(_ address: UInt64,
                               registers: inout LinuxGeneralRegisters) {
    registers.program = address
  }

  internal static func program(_ registers: borrowing LinuxGeneralRegisters)
      -> UInt64 {
    registers.program
  }

  internal static func result(_ registers: borrowing LinuxGeneralRegisters)
      -> UInt64 {
    registers.values[0]
  }
}
#endif
