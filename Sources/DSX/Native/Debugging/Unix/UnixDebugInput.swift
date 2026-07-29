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

internal func write(_ descriptor: CInt, bytes: borrowing Span<UInt8>)
    throws(Debuggee.Error) {
  try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
    var offset = 0
    while offset < bytes.count {
      let base = bytes.baseAddress!.advanced(by: offset)
      let count = DSX::write(descriptor, base, bytes.count - offset,
                             suppressing: SIGPIPE)
      if count > 0 {
        offset += count
        continue
      }
      if count < 0, errno == EINTR {
        continue
      }
      throw UnixDebugProcess.failure(count < 0 ? errno : EIO)
    }
  }
}
#endif
