// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension String {
  internal init(decodingCString value: borrowing Array<WCHAR>,
                as _: UTF16.Type) {
    self = value.withUnsafeBufferPointer { value in
      String(decodingCString: value.baseAddress!, as: UTF16.self)
    }
  }
}
#endif

extension String {
  internal init(decoding bytes: borrowing Span<UInt8>, as _: UTF8.Type) {
    self = bytes.withUnsafeBytes { bytes in
      String(decoding: bytes, as: UTF8.self)
    }
  }
}
