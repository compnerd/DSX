// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK
#elseif os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

extension Host {
  internal static var time: UInt64 {
    get throws(Debuggee.Error) {
#if os(Windows)
      GetTickCount64()
#else
      var value = timespec()
      guard clock_gettime(CLOCK_MONOTONIC, &value) == 0 else {
        throw .system(errno)
      }
      return UInt64(value.tv_sec) * 1_000 + UInt64(value.tv_nsec) / 1_000_000
#endif
    }
  }
}
