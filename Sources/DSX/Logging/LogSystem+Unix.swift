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

extension LogSystem {
  internal static var error: CInt {
    STDERR_FILENO
  }

  internal static func open(_ path: String, append: Bool) throws(LogError)
      -> CInt {
    let disposition = append ? O_APPEND : O_TRUNC
    let descriptor = path.withCString { path in
      DSX::open(path, O_WRONLY | O_CREAT | O_CLOEXEC | disposition, 0o644)
    }
    guard descriptor >= 0 else {
      throw .open(errno)
    }
    return descriptor
  }

  internal static func close(_ descriptor: CInt) {
    _ = DSX::close(descriptor)
  }

  internal static func terminal(_ descriptor: CInt) -> Bool {
    isatty(descriptor) != 0
  }

  internal static func output(_ descriptor: CInt, _ buffer: UnsafeRawPointer,
                              _ count: Int) -> Int {
    while true {
      let result = DSX::write(descriptor, buffer, count)
      if result >= 0 {
        return result
      }
      guard errno == EINTR else {
        return -1
      }
    }
  }
}
#endif
