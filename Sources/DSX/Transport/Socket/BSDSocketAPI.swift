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

internal enum BSDSocketAPI {
  internal static var stream: CInt {
#if os(anyAppleOS)
    SOCK_STREAM
#elseif os(Linux)
    CInt(SOCK_STREAM.rawValue)
#elseif os(Android)
    SOCK_STREAM
#else
    SOCK_STREAM.rawValue
#endif
  }

  internal static var tcp: CInt {
#if os(Android) || os(Linux)
    CInt(IPPROTO_TCP)
#else
    IPPROTO_TCP
#endif
  }

  internal static var ipv6: CInt {
#if os(Android) || os(Linux)
    CInt(IPPROTO_IPV6)
#else
    IPPROTO_IPV6
#endif
  }

  internal static var flags: CInt {
#if os(anyAppleOS)
    0
#elseif os(Android) || os(Linux)
    CInt(MSG_NOSIGNAL)
#else
    MSG_NOSIGNAL
#endif
  }

  internal static func prepare(_ address: inout sockaddr_un) {
#if os(anyAppleOS) || os(FreeBSD) || os(OpenBSD)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
#endif
    address.sun_family = sa_family_t(AF_UNIX)
  }
}
#endif
