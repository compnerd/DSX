// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

internal enum UnixError {
  internal static func breakpoint(_ code: CInt) -> Debuggee.Error {
    switch code {
    case EINVAL, EIO: .breakpoint
    case EACCES, EPERM: .access
    case ESRCH: .thread
    case ENOSYS, ENOTSUP: .unsupported
    default: .system(code)
    }
  }

  internal static func filesystem(_ code: CInt) -> Debuggee.Error {
    debuggee(code, invalid: .system(code), support: true)
  }

  internal static func memory(_ code: CInt) -> Debuggee.Error {
    switch code {
    case EFAULT, EIO: .memory
    default: debuggee(code, invalid: .process, support: true)
    }
  }

  internal static func register(_ code: CInt) -> Debuggee.Error {
    switch code {
    case EACCES, EPERM: .access
    case ESRCH: .thread
    case EINVAL: .unsupported
    default: .system(code)
    }
  }

  internal static func debuggee(_ code: CInt, invalid: Debuggee.Error,
                                support: Bool = false) -> Debuggee.Error {
    if support, code == ENOSYS || code == ENOTSUP {
      return .unsupported
    }
    return switch code {
    case EACCES, EPERM: .access
    case ENOENT, ESRCH: invalid
    default: .system(code)
    }
  }
}
#endif
