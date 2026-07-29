// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum SignalName {
  case fixed(StaticString)
  case realtime(Int)
}

internal enum SignalCatalog {
  internal static let kSuppress: UInt8 = 0x01
  internal static let kStop: UInt8 = 0x02
  internal static let kNotify: UInt8 = 0x04

#if os(Android) || os(Linux)
  private static let kName: InlineArray<31, StaticString> = [
    "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP", "SIGABRT",
    "SIGBUS", "SIGFPE", "SIGKILL", "SIGUSR1", "SIGSEGV", "SIGUSR2",
    "SIGPIPE", "SIGALRM", "SIGTERM", "SIGSTKFLT", "SIGCHLD", "SIGCONT",
    "SIGSTOP", "SIGTSTP", "SIGTTIN", "SIGTTOU", "SIGURG", "SIGXCPU",
    "SIGXFSZ", "SIGVTALRM", "SIGPROF", "SIGWINCH", "SIGIO", "SIGPWR",
    "SIGSYS",
  ]
#else
  private static let kName: InlineArray<31, StaticString> = [
    "SIGHUP", "SIGINT", "SIGQUIT", "SIGILL", "SIGTRAP", "SIGABRT",
    "SIGEMT", "SIGFPE", "SIGKILL", "SIGBUS", "SIGSEGV", "SIGSYS",
    "SIGPIPE", "SIGALRM", "SIGTERM", "SIGURG", "SIGSTOP", "SIGTSTP",
    "SIGCONT", "SIGCHLD", "SIGTTIN", "SIGTTOU", "SIGIO", "SIGXCPU",
    "SIGXFSZ", "SIGVTALRM", "SIGPROF", "SIGWINCH", "SIGINFO", "SIGUSR1",
    "SIGUSR2",
  ]
#endif

  @inline(__always)
  internal static func visit<E: Error>(_ body: (Int) throws(E) -> Void)
      throws(E) {
#if os(Android) || os(Linux)
    for signal in 1 ... 64 {
      try body(signal)
    }
#elseif os(FreeBSD)
    for signal in 1 ... 33 {
      try body(signal)
    }
    for signal in 65 ... 126 {
      try body(signal)
    }
#elseif os(OpenBSD)
    for signal in 1 ... 32 {
      try body(signal)
    }
#else
    for signal in 1 ... 31 {
      try body(signal)
    }
#endif
  }

  @inline(__always)
  internal static func name(_ signal: Int) -> SignalName {
    if signal <= kName.count {
      return .fixed(kName[signal - 1])
    }
#if os(Android) || os(Linux)
    return switch signal {
    case 32: .fixed("SIG32")
    case 33: .fixed("SIG33")
    default: .realtime(signal - 34)
    }
#elseif os(FreeBSD) || os(OpenBSD)
    return switch signal {
    case 32: .fixed("SIGTHR")
    case 33: .fixed("SIGLIBRT")
    default: .realtime(signal - 65)
    }
#else
    return SignalName.fixed("")
#endif
  }

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

  @inline(__always)
  internal static func gdb(_ signal: CInt) -> UInt8 {
#if os(Android) || os(Linux)
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
#else
    switch signal {
    case 29: 142
#if os(FreeBSD) || os(OpenBSD)
    case 32: 37
    case 33: 151
#endif
    default: UInt8(truncatingIfNeeded: signal)
    }
#endif
  }

  @inline(__always)
  internal static func native(_ signal: UInt64) -> CInt? {
    guard signal <= UInt8.max else {
      return nil
    }
#if os(Android) || os(Linux)
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
#else
    return switch signal {
    case 29, 32 ... 141, 143 ... 150, 152 ... 255: nil
    case 142: 29
#if os(FreeBSD) || os(OpenBSD)
    case 37: 32
    case 151: 33
#else
    case 151: nil
#endif
    default: CInt(signal)
    }
#endif
  }
}
