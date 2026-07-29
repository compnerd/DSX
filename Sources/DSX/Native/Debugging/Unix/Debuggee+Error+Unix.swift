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
  internal var message: String {
    if case .denied = self {
      return "attach denied by ptrace(PT_DENY_ATTACH)"
    }
    guard case .launch(let code) = self, let message = strerror(code) else {
      return description
    }
    return "execve failed: \(String(cString: message))"
  }
}
#endif
