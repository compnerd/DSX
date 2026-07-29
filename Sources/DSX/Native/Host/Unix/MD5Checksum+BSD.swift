// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) || os(FreeBSD) || os(OpenBSD)
internal import DSXShims

internal struct MD5Checksum: ~Copyable {
#if os(anyAppleOS)
  private var context = CC_MD5_CTX()
#else
  private var context = MD5_CTX()
#endif

  internal init() throws(Debuggee.Error) {
#if os(anyAppleOS)
    dsx_md5_init(&context)
#else
    MD5Init(&context)
#endif
  }

  internal mutating func update(_ bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    bytes.withUnsafeBytes { bytes in
      var offset = 0
      while offset < bytes.count {
        let count = UInt32(clamping: bytes.count - offset)
        let address = bytes.baseAddress!.advanced(by: offset)
#if os(anyAppleOS)
        dsx_md5_update(&context, address, count)
#elseif os(FreeBSD)
        MD5Update(&context, address, count)
#else
        MD5Update(&context, address.assumingMemoryBound(to: UInt8.self),
                  Int(count))
#endif
        offset += Int(count)
      }
    }
  }

  internal consuming func finish() throws(Debuggee.Error)
      -> InlineArray<16, UInt8> {
    var digest = InlineArray<16, UInt8> { _ in 0 }
    withUnsafeMutableBytes(of: &digest) { bytes in
      let output = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
#if os(anyAppleOS)
      dsx_md5_final(output, &context)
#else
      MD5Final(output, &context)
#endif
    }
    return digest
  }
}
#endif
