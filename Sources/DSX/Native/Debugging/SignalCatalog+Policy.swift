// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension SignalCatalog {
  internal static let kSuppress: UInt8 = 0x01
  internal static let kStop: UInt8 = 0x02
  internal static let kNotify: UInt8 = 0x04

  @inline(__always)
  internal static func policy(_ signal: Int) -> UInt8 {
#if os(Android) || os(Linux)
    let suppressed: UInt8 =
        signal == 2 || signal == 5 || signal == 19 ? kSuppress : 0
    let behavior: UInt8 = switch signal {
    case 17, 18: kNotify
    case 14, 27, 28, 32 ... 64: 0
    default: kStop | kNotify
    }
#else
    let suppressed: UInt8 =
        signal == 2 || signal == 5 || signal == 17 ? kSuppress : 0
    let behavior: UInt8 = switch signal {
    case 19: kNotify
    case 13, 14, 16, 20, 23, 26, 27, 28, 32 ... Int.max: 0
    default: kStop | kNotify
    }
#endif
    return suppressed | behavior
  }
}
