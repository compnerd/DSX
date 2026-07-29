// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(i386) || arch(x86_64)
extension ABI {
  internal static func size(_ address: Debuggee.Address, requested: Int)
      throws(Debuggee.Error) -> Int {
    guard requested == 1 else {
      throw .breakpoint
    }
    return 1
  }

  internal static func breakpoint(_ size: Int,
                                  into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard size == 1 else {
      throw .breakpoint
    }
    output.append(0xcc)
  }
}
#elseif arch(riscv64)
extension ABI {
  internal static func size(_ address: Debuggee.Address, requested: Int)
      throws(Debuggee.Error) -> Int {
    guard requested == 2 || requested == 4,
        address.rawValue.isMultiple(of: UInt64(requested)) else {
      throw .breakpoint
    }
    return requested
  }

  internal static func breakpoint(_ size: Int,
                                  into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch size {
    case 2:
      output.append(0x02)
      output.append(0x90)
    case 4:
      output.append(0x73)
      output.append(0x00)
      output.append(0x10)
      output.append(0x00)
    default:
      throw .breakpoint
    }
  }
}
#endif

extension ABI {
  internal enum SoftwareBreakpoint {
    internal static var capacity: Int {
      4
    }
  }

  internal static func address(_ stop: Debuggee.Stop) -> Debuggee.Address? {
    stop.fault?.address
  }
}
