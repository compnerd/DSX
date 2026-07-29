// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
extension GDBSignal {
  @inline(__always)
  internal static func gdb(_ signal: CInt) -> UInt8 {
    switch signal {
    case 7: 10
    case 10: 30
    case 12: 31
    case 16: 143
    case 17: 20
    case 18: 19
    case 19: 17
    case 20: 18
    case 23: 16
    case 29: 23
    case 30: 32
    case 31: 12
    case 32: 77
    case 33 ... 63: UInt8(signal + 12)
    case 64: 78
    default: UInt8(truncatingIfNeeded: signal)
    }
  }

  @inline(__always)
  internal static func native(_ signal: UInt64) -> CInt? {
    guard signal <= UInt8.max else {
      return nil
    }
    return switch signal {
    case 7, 29, 34 ... 44, 76, 79 ... 142, 144 ... 255: nil
    case 10: 7
    case 12: 31
    case 16: 23
    case 17: 19
    case 18: 20
    case 19: 18
    case 20: 17
    case 23, 33: 29
    case 30: 10
    case 31: 12
    case 32: 30
    case 45 ... 75: CInt(signal - 12)
    case 77: 32
    case 78: 64
    case 143: 16
    default: CInt(signal)
    }
  }
}
#endif
