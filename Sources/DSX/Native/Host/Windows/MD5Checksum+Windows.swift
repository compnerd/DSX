// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal struct MD5Checksum: ~Copyable {
  private let handle: BCRYPT_HASH_HANDLE

  internal init() throws(Debuggee.Error) {
    var handle: BCRYPT_HASH_HANDLE?
    let status =
        BCryptCreateHash(BCRYPT_MD5_ALG_HANDLE, &handle, nil, 0, nil, 0, 0)
    guard status >= 0, let handle else {
      throw .checksum
    }
    self.handle = handle
  }

  deinit {
    _ = BCryptDestroyHash(handle)
  }

  internal mutating func update(_ bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      var offset = 0
      while offset < bytes.count {
        let count = ULONG(clamping: bytes.count - offset)
        let address = bytes.baseAddress!.advanced(by: offset)
        let input = UnsafeMutableRawPointer(mutating: address)
        guard BCryptHashData(handle, input.assumingMemoryBound(to: UInt8.self),
                             count, 0) >= 0 else {
          throw .checksum
        }
        offset += Int(count)
      }
    }
  }

  internal consuming func finish() throws(Debuggee.Error)
      -> InlineArray<16, UInt8> {
    var digest = InlineArray<16, UInt8> { _ in 0 }
    let status = withUnsafeMutableBytes(of: &digest) { bytes in
      let output = bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
      return BCryptFinishHash(handle, output, ULONG(bytes.count), 0)
    }
    guard status >= 0 else {
      throw .checksum
    }
    return digest
  }
}
#endif
