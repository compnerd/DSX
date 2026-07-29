// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
extension Host {
  internal static var system: StaticString {
#if os(Android)
    "android"
#else
    "linux"
#endif
  }

  internal static var version: String? {
    release.flatMap { version($0) }
  }

  internal static func version(_ release: borrowing String) -> String? {
    var count = 0
    var end = 0
    for byte in release.utf8 {
      if (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(byte) {
        count += 1
        end = count
        continue
      }
      guard byte == UInt8(ascii: "."), count == end, count > 0 else {
        break
      }
      count += 1
    }
    guard end > 0 else {
      return nil
    }
    return String(decoding: release.utf8.prefix(end), as: UTF8.self)
  }

  internal static var metadata: HostMetadata {
#if os(Android)
    HostMetadata(platform: "linux-android", system: "linux",
                 environment: "android")
#else
    HostMetadata(system: "linux", environment: "gnu")
#endif
  }
}
#endif
