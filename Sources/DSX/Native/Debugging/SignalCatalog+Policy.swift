// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

extension SignalCatalog {
  internal static let kSuppress: UInt8 = 0x01
  internal static let kStop: UInt8 = 0x02
  internal static let kNotify: UInt8 = 0x04

  @inline(__always)
  internal static func policy(_ signal: Int) -> UInt8 {
#if os(Android) || os(Linux)
    let suppress = signal == SIGINT || signal == SIGTRAP || signal == SIGSTOP
    let suppressed: UInt8 = suppress ? kSuppress : 0
    let behavior: UInt8 = switch signal {
    case Int(SIGCHLD), Int(SIGCONT): kNotify
    // Include the two kernel realtime signals reserved by glibc.
    case Int(SIGALRM), Int(SIGPROF), Int(SIGWINCH), 32 ... 64: 0
    default: kStop | kNotify
    }
#elseif os(Windows)
    // Windows reports the protocol's BSD signal catalog, not CRT signals.
    let suppressed: UInt8 =
        signal == 2 || signal == 5 || signal == 17 ? kSuppress : 0
    let behavior: UInt8 = switch signal {
    case 19: kNotify
    case 13, 14, 16, 20, 23, 26, 27, 28, 32 ... Int.max: 0
    default: kStop | kNotify
    }
#else
    let suppress = signal == SIGINT || signal == SIGTRAP || signal == SIGSTOP
    let suppressed: UInt8 = suppress ? kSuppress : 0
    let behavior: UInt8 = switch signal {
    case Int(SIGCONT): kNotify
    case Int(SIGPIPE), Int(SIGALRM), Int(SIGURG), Int(SIGCHLD), Int(SIGIO),
         Int(SIGVTALRM), Int(SIGPROF), Int(SIGWINCH), 32 ... Int.max: 0
    default: kStop | kNotify
    }
#endif
    return suppressed | behavior
  }
}
