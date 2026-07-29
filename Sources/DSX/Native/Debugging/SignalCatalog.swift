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
}
