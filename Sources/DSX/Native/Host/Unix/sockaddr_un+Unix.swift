// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

extension sockaddr_un {
  internal init(_ path: String) throws(TransportError) {
    self.init()
    let capacity = MemoryLayout.size(ofValue: sun_path)
    let count = path.utf8.count
    guard count < capacity else {
      throw .path
    }
#if os(anyAppleOS) || os(FreeBSD) || os(OpenBSD)
    sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
#endif
    sun_family = sa_family_t(AF_UNIX)
    path.withCString { source in
      withUnsafeMutableBytes(of: &sun_path) { destination in
        destination.copyBytes(from: UnsafeRawBufferPointer(start: source,
                                                           count: count + 1))
      }
    }
  }
}
#endif
