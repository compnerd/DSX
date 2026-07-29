// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension NativeStream {
  internal static func output(_ bytes: borrowing Span<UInt8>)
      throws(TransportError) {
    try bytes.withUnsafeBytes { bytes throws(TransportError) in
      var offset = 0
      while offset < bytes.count {
        let base = bytes.baseAddress!.advanced(by: offset)
        offset += try output(base, count: bytes.count - offset)
      }
    }
  }
}
