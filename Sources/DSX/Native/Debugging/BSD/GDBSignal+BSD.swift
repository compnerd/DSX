// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) || os(Windows) || os(FreeBSD) || os(OpenBSD)
extension GDBSignal {
  @inline(__always)
  internal static func gdb(_ signal: CInt) -> UInt8 {
    switch signal {
    case 29: 142
#if os(FreeBSD) || os(OpenBSD)
    case 32: 37
#endif
#if os(FreeBSD)
    case 33: 151
    case 65 ... 126: UInt8(signal + 14)
#endif
    default: UInt8(truncatingIfNeeded: signal)
    }
  }

  @inline(__always)
  internal static func native(_ signal: UInt64) -> CInt? {
    guard signal <= UInt8.max else {
      return nil
    }
    return switch signal {
    case 0 ... 28, 30, 31: CInt(signal)
    case 142: 29
#if os(FreeBSD) || os(OpenBSD)
    case 37: 32
#endif
#if os(FreeBSD)
    case 151: 33
    case 79 ... 140: CInt(signal - 14)
#endif
    default: nil
    }
  }
}
#endif
