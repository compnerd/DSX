// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import CRT
#elseif os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

package func output(_ value: String, error: Bool = false) {
  let descriptor = error ? STDERR_FILENO : STDOUT_FILENO
  value.withCString { bytes in
    write(bytes, count: strlen(bytes), descriptor: descriptor)
  }
  "\n".withCString { bytes in
    write(bytes, count: 1, descriptor: descriptor)
  }
}

package func terminate(_ status: CInt) -> Never {
#if os(Windows)
  CRT._exit(status)
#elseif os(anyAppleOS)
  Darwin._exit(status)
#elseif os(Android)
  Android._exit(status)
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
  Glibc._exit(status)
#endif
}

private func write(_ bytes: UnsafePointer<CChar>, count: Int,
                   descriptor: CInt) {
  var offset = 0
  while offset < count {
#if os(Windows)
    let result =
        _write(descriptor, bytes.advanced(by: offset), UInt32(count - offset))
#else
    let result = write(descriptor, bytes.advanced(by: offset), count - offset)
#endif
    if result > 0 {
      offset += Int(result)
      continue
    }
#if !os(Windows)
    if errno == EINTR {
      continue
    }
#endif
    return
  }
}
