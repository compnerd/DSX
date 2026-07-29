// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android)
internal import Crypto

internal struct MD5Checksum: ~Copyable {
  private var context = Insecure.MD5()

  internal init() throws(Debuggee.Error) {}

  internal mutating func update(_ bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    bytes.withUnsafeBytes { bytes in
      context.update(bufferPointer: bytes)
    }
  }

  internal consuming func finish() throws(Debuggee.Error)
      -> InlineArray<16, UInt8> {
    let result = context.finalize()
    var digest = InlineArray<16, UInt8> { _ in 0 }
    withUnsafeMutableBytes(of: &digest) { output in
      result.withUnsafeBytes { input in
        output.copyBytes(from: input)
      }
    }
    return digest
  }
}
#endif
