// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm)
extension ABI {
  internal static func breakpoint(_ program: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    program
  }

  internal static func completes(_ code: CInt) -> Bool {
    code == TRAP_TRACE
  }
}

extension LinuxGeneralRegisters {
  internal func instruction(into bytes: inout InlineArray<4, UInt8>) -> Int {
    if values[16] & 0x20 == 0x20 {
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

  internal mutating func prepare(_ arguments: borrowing Span<UInt64>)
      throws(Debuggee.Error) {
    guard arguments.count > 0, arguments.count <= 7 else {
      throw .state
    }
    values[7] = UInt32(truncatingIfNeeded: arguments[0])
    for index in 1 ..< arguments.count {
      values[index - 1] = UInt32(truncatingIfNeeded: arguments[index])
    }
  }

  internal mutating func set(pc: UInt64) {
    values[15] = UInt32(truncatingIfNeeded: pc)
  }

  internal var program: UInt64 {
    UInt64(values[15])
  }

  internal var returned: UInt64 {
    UInt64(bitPattern: Int64(Int32(bitPattern: values[0])))
  }

  internal var syscall: UInt64 {
    UInt64(values[7])
  }
}
#endif
