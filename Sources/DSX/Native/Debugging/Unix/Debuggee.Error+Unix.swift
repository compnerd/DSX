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
  internal init(breakpoint code: CInt) {
    self = switch code {
    case EINVAL, EIO: .breakpoint
    case EACCES, EPERM: .access
    case ESRCH: .thread
    case ENOSYS, ENOTSUP: .unsupported
    default: .system(code)
    }
  }

  internal init(memory code: CInt) {
    self = switch code {
    case EFAULT, EIO: .memory
    default: Debuggee.Error(unix: code, invalid: .process, support: true)
    }
  }

  internal init(register code: CInt) {
    self = switch code {
    case EACCES, EPERM: .access
    case ESRCH: .thread
    case EINVAL: .unsupported
    default: .system(code)
    }
  }

  internal var message: String {
    if case .denied = self {
      return "attach denied by ptrace(PT_DENY_ATTACH)"
    }
    guard case .launch(let code) = self, let message = strerror(code) else {
      return description
    }
    return "execve failed: \(String(cString: message))"
  }

  internal init(unix code: CInt) {
    self = if code == EINVAL {
      .state
    } else {
      Debuggee.Error(unix: code, invalid: .process, support: true)
    }
  }
}
#endif
