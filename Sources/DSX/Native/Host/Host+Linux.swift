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
    release
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
