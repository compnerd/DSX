// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) || os(Android) || os(Linux) || os(FreeBSD) || os(OpenBSD)
extension String {
  internal init(native bytes: UnsafeRawBufferPointer) {
    let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
    self.init(decoding: bytes[..<end], as: UTF8.self)
  }
}
#endif
