// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm)
private let PSR_T_BIT: UInt32 = 0x0000_0020
private let PSR_J_BIT: UInt32 = 0x0100_0000
private let PSR_IT_MASK: UInt32 = 0x0600_fc00
private let BREAKINST_ARM: UInt32 = 0xe7f0_01f0
private let BREAKINST_THUMB: UInt16 = 0xde01
private let kThumbSVC: UInt16 = 0xdf00

extension ABI {
  internal static func breakpoint(_ size: Int,
                                  into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let instruction: UInt32 = switch size {
    case 2: UInt32(BREAKINST_THUMB)
    case 4: BREAKINST_ARM
    default: throw .breakpoint
    }
    withUnsafeBytes(of: instruction.littleEndian) { bytes in
      for byte in bytes.prefix(size) {
        output.append(byte)
      }
    }
  }

  internal static func breakpoint(_ program: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    program
  }

  internal static func completes(_ code: CInt) -> Bool {
    code == TRAP_BRKPT
  }
}

extension LinuxGeneralRegisters {
  internal func instruction(into bytes: inout InlineArray<4, UInt8>) -> Int {
    // Thumb SVC followed by Linux's Thumb breakpoint fits one ptrace word.
    let instruction = UInt32(kThumbSVC) | UInt32(BREAKINST_THUMB) << 16
    withUnsafeMutableBytes(of: &bytes) { bytes in
      bytes.storeBytes(of: instruction.littleEndian, as: UInt32.self)
    }
    return 2
  }

  internal mutating func prepare(_ arguments: borrowing Span<UInt64>)
      throws(Debuggee.Error) {
    guard arguments.count > 0, arguments.count <= 7 else {
      throw .state
    }
    // The injected sequence is unconditional Thumb, even for an ARM caller
    // or a thread stopped in an IT block. Restore the saved CPSR afterward.
    values[16] = values[16] & ~(PSR_J_BIT | PSR_IT_MASK) | PSR_T_BIT
    values[7] = UInt32(truncatingIfNeeded: arguments[0])
    for index in 1 ..< arguments.count {
      values[index - 1] = UInt32(truncatingIfNeeded: arguments[index])
    }
  }

  internal mutating func set(pc: UInt64) {
    values[15] = UInt32(truncatingIfNeeded: pc)
  }

  internal var pc: UInt64 {
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
