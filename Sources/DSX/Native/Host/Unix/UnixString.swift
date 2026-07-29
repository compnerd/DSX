// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) || os(Android) || os(Linux) || os(FreeBSD) || os(OpenBSD)
internal func decode<Value>(_ value: inout Value) -> String {
  withUnsafeBytes(of: &value) { bytes in
    let end = bytes.firstIndex(of: 0) ?? bytes.endIndex
    return String(decoding: bytes[..<end], as: UTF8.self)
  }
}
#endif
