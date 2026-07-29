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

  internal static func completes(_ code: CInt) -> Bool {
    code == TRAP_BRKPT || code == TRAP_TRACE
  }

}

extension LinuxGeneralRegisters {
  internal func instruction(into bytes: inout InlineArray<4, UInt8>) -> Int {
    bytes[0] = 0xcd
    bytes[1] = 0x80
    return 2
  }

  internal mutating func prepare(_ arguments: borrowing Span<UInt64>)
      throws(Debuggee.Error) {
    guard arguments.count > 0, arguments.count <= 7 else {
      throw .state
    }
    eax = UInt32(truncatingIfNeeded: arguments[0])
    if arguments.count > 1 {
      ebx = UInt32(truncatingIfNeeded: arguments[1])
    }
    if arguments.count > 2 {
      ecx = UInt32(truncatingIfNeeded: arguments[2])
    }
    if arguments.count > 3 {
      edx = UInt32(truncatingIfNeeded: arguments[3])
    }
    if arguments.count > 4 {
      esi = UInt32(truncatingIfNeeded: arguments[4])
    }
    if arguments.count > 5 {
      edi = UInt32(truncatingIfNeeded: arguments[5])
    }
    if arguments.count > 6 {
      ebp = UInt32(truncatingIfNeeded: arguments[6])
    }
  }

  internal mutating func set(pc: UInt64) {
    // Redirected execution must not restart an interrupted kernel syscall.
    origin = UInt32.max
    program = UInt32(truncatingIfNeeded: pc)
  }

  internal var returned: UInt64 {
    UInt64(bitPattern: Int64(Int32(bitPattern: eax)))
  }

  internal var syscall: UInt64 {
    UInt64(origin)
  }
}
#endif
