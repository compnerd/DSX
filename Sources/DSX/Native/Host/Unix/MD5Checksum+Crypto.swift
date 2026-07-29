// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Linux)
internal import DSXShims

internal struct MD5Checksum: ~Copyable {
  private let context: dsx_digest_context

  internal init() throws(Debuggee.Error) {
    guard let context = EVP_MD_CTX_new() else {
      throw .checksum
    }
    guard EVP_DigestInit_ex(context, EVP_md5(), nil) == 1 else {
      EVP_MD_CTX_free(context)
      throw .checksum
    }
    self.context = context
  }

  deinit {
    EVP_MD_CTX_free(context)
  }

  internal mutating func update(_ bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    let status = bytes.withUnsafeBytes { bytes in
      EVP_DigestUpdate(context, bytes.baseAddress, bytes.count)
    }
    guard status == 1 else {
      throw .checksum
    }
  }

  internal consuming func finish() throws(Debuggee.Error)
      -> InlineArray<16, UInt8> {
    var digest = InlineArray<16, UInt8> { _ in 0 }
    let status = withUnsafeMutableBytes(of: &digest) { bytes in
      let output = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
      return EVP_DigestFinal_ex(context, output, nil)
    }
    guard status == 1 else {
      throw .checksum
    }
    return digest
  }
}
#endif
