// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(x86_64)
extension ABI {
  internal static func breakpoint(_ program: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    guard program > 0 else {
      throw .register
    }
    return program - 1
  }

  internal static var map: UInt64 { 9 }
  internal static var unmap: UInt64 { 11 }
  internal static var word: Int { 8 }

  internal static func instruction(_: borrowing LinuxGeneralRegisters,
                                   into bytes: inout InlineArray<4, UInt8>)
      -> Int {
    bytes[0] = 0x0f
    bytes[1] = 0x05
    return 2
  }

  internal static func prepare(_ arguments: borrowing Span<UInt64>,
                               registers: inout LinuxGeneralRegisters)
      throws(Debuggee.Error) {
    guard arguments.count > 0, arguments.count <= 7 else {
      throw .state
    }
    registers.rax = arguments[0]
    if arguments.count > 1 {
      registers.rdi = arguments[1]
    }
    if arguments.count > 2 {
      registers.rsi = arguments[2]
    }
    if arguments.count > 3 {
      registers.rdx = arguments[3]
    }
    if arguments.count > 4 {
      registers.r10 = arguments[4]
    }
    if arguments.count > 5 {
      registers.r8 = arguments[5]
    }
    if arguments.count > 6 {
      registers.r9 = arguments[6]
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
    registers.rax
  }
}
#endif
