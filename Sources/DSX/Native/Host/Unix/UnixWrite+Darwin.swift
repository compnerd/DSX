// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal enum WritePolicy {
  internal static func write(_ handle: CInt, _ bytes: UnsafeRawPointer?,
                             _ count: Int, suppressing _: CInt) -> Int {
    guard fcntl(handle, F_SETNOSIGPIPE, 1) == 0 else {
      return -1
    }
    return DSX::write(handle, bytes, count)
  }
}
#endif
