// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
extension ABI {
  internal static func breakpoint(_ program: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    program
  }

  internal static func completes(_ code: CInt) -> Bool {
    code == TRAP_TRACE || code == SI_USER
  }
}

extension LinuxGeneralRegisters {
  internal func instruction(into bytes: inout InlineArray<4, UInt8>) -> Int {
    bytes[0] = 0x01
    bytes[1] = 0x00
    bytes[2] = 0x00
    bytes[3] = 0xd4
    return 4
  }

  internal mutating func prepare(_ arguments: borrowing Span<UInt64>)
      throws(Debuggee.Error) {
    guard arguments.count > 0, arguments.count <= 7 else {
      throw .state
    }
    values[8] = arguments[0]
    for index in 1 ..< arguments.count {
      values[index - 1] = arguments[index]
    }
  }

  internal mutating func set(pc: UInt64) {
    program = pc
  }

  internal var returned: UInt64 {
    values[0]
  }

  internal var syscall: UInt64 {
    values[8]
  }
}
#endif
