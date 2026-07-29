// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(arm) || arch(arm64))
extension ABI {
#if arch(arm)
  internal static func size(_ address: Debuggee.Address,
                            requested: Int) throws(Debuggee.Error) -> Int {
    guard requested == 2, address.rawValue.isMultiple(of: 2) else {
      throw .breakpoint
    }
    return 2
  }
#endif

  internal static func breakpoint(_ size: Int,
                                  into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
#if arch(arm64)
    guard size == 4 else {
      throw .breakpoint
    }
    output.append(0x00)
    output.append(0x00)
    output.append(0x3e)
    output.append(0xd4)
#else
    guard size == 2 else {
      throw .breakpoint
    }
    output.append(0xfe)
    output.append(0xde)
#endif
  }
}
#endif
