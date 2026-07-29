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

extension Debuggee.Error {
  internal init(process code: CInt) {
    self.init(unix: code, invalid: .process, support: true)
  }

  internal init(filesystem code: CInt) {
    self.init(unix: code, invalid: .system(code), support: true)
  }

  internal init(unix code: CInt, invalid: Debuggee.Error,
                support: Bool = false) {
    if support, code == ENOSYS || code == ENOTSUP {
      self = .unsupported
      return
    }
    self = switch code {
    case EACCES, EPERM: .access
    case ENOENT, ESRCH: invalid
    default: .system(code)
    }
  }
}
#endif
