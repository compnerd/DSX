// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(i386)
extension ABI {
  internal static func breakpoint(_ program: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    guard program > 0 else {
      throw .register
    }
    return program - 1
  }

  internal static var map: UInt64 { 192 }
  internal static var unmap: UInt64 { 91 }
  internal static var word: Int { 4 }

  internal static func instruction(_: borrowing LinuxGeneralRegisters,
                                   into bytes: inout InlineArray<4, UInt8>)
      -> Int {
    bytes[0] = 0xcd
    bytes[1] = 0x80
    return 2
  }

  internal static func prepare(_ arguments: borrowing Span<UInt64>,
                               registers: inout LinuxGeneralRegisters)
      throws(Debuggee.Error) {
    guard arguments.count > 0, arguments.count <= 7 else {
      throw .state
    }
    registers.eax = UInt32(truncatingIfNeeded: arguments[0])
    if arguments.count > 1 {
      registers.ebx = UInt32(truncatingIfNeeded: arguments[1])
    }
    if arguments.count > 2 {
      registers.ecx = UInt32(truncatingIfNeeded: arguments[2])
    }
    if arguments.count > 3 {
      registers.edx = UInt32(truncatingIfNeeded: arguments[3])
    }
    if arguments.count > 4 {
      registers.esi = UInt32(truncatingIfNeeded: arguments[4])
    }
    if arguments.count > 5 {
      registers.edi = UInt32(truncatingIfNeeded: arguments[5])
    }
    if arguments.count > 6 {
      registers.ebp = UInt32(truncatingIfNeeded: arguments[6])
    }
  }

  internal static func program(_ address: UInt64,
                               registers: inout LinuxGeneralRegisters) {
    registers.program = UInt32(truncatingIfNeeded: address)
  }

  internal static func program(_ registers: borrowing LinuxGeneralRegisters)
      -> UInt64 {
    UInt64(registers.program)
  }

  internal static func result(_ registers: borrowing LinuxGeneralRegisters)
      -> UInt64 {
    UInt64(bitPattern: Int64(Int32(bitPattern: registers.eax)))
  }
}
#endif
