// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
extension Host {
  internal static var system: StaticString {
#if os(FreeBSD)
    "freebsd"
#else
    "openbsd"
#endif
  }

  internal static var version: String? {
    release
  }

  internal static var metadata: HostMetadata {
    HostMetadata()
  }
}
#endif
