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

extension ProcessIdentifier {
  @_transparent
  internal var native: pid_t {
    get throws(Debuggee.Error) {
      guard rawValue <= UInt64(pid_t.max) else {
        throw .process
      }
      return pid_t(rawValue)
    }
  }

  internal func owned(by current: ProcessIdentifier?) throws(Debuggee.Error)
      -> pid_t {
    guard current == self else {
      throw .process
    }
    return try native
  }
}

extension ThreadIdentifier {
  @_transparent
  internal var native: pid_t {
    get throws(Debuggee.Error) {
      guard rawValue <= UInt64(pid_t.max) else {
        throw .thread
      }
      return pid_t(rawValue)
    }
  }
}

extension ProcessThreadIdentifier {
  @_transparent
  internal var native: pid_t {
    get throws(Debuggee.Error) {
      guard process.rawValue <= UInt64(pid_t.max),
          thread.rawValue <= UInt64(pid_t.max) else {
        throw .thread
      }
      return pid_t(thread.rawValue)
    }
  }
}
#endif
