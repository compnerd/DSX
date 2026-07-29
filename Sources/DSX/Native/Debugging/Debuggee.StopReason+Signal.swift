// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

extension Debuggee.StopReason {
  /// The host signal underlying a stop, when it has one.
  internal var signal: CInt? {
    switch self {
    case let .signal(value): value
    case .interrupt:
#if os(Windows)
      nil
#else
      SIGSTOP
#endif
    default: nil
    }
  }
}
