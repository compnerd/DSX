// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) || os(Linux) || os(Android) || os(FreeBSD) || os(OpenBSD)
#if arch(arm) || arch(arm64)
extension ABI {
#if arch(arm)
  internal static func size(_ address: Debuggee.Address,
                            requested: Int) throws(Debuggee.Error) -> Int {
    guard requested == 2 || requested == 4 else {
      throw .breakpoint
    }
    return requested
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
    output.append(0x20)
    output.append(0xd4)
#else
    switch size {
    case 2:
      output.append(0x00)
      output.append(0xbe)
    case 4:
      output.append(0x70)
      output.append(0x00)
      output.append(0x20)
      output.append(0xe1)
    default:
      throw .breakpoint
    }
#endif
  }
}
#endif
#endif
