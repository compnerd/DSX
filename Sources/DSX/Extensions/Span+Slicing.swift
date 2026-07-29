// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Span where Element == UInt8 {
  @inline(__always)
  @_lifetime(copy self)
  internal func slice(at offset: UInt64, count: UInt64, stride: UInt64)
      throws(Debuggee.Error) -> Span<UInt8> {
    guard count > 0 else {
      return extracting(0 ..< 0)
    }
    guard stride > 0, offset <= UInt64(self.count),
        count <= (UInt64(self.count) - offset) / stride else {
      throw .process
    }
    return try slice(at: offset, size: count * stride)
  }

  @inline(never)
  @_lifetime(copy self)
  internal func slice(at offset: UInt64, size: UInt64) throws(Debuggee.Error)
      -> Span<UInt8> {
    guard offset <= UInt64(count), size <= UInt64(count) - offset else {
      throw .process
    }
    let start = Int(offset)
    return extracting(start ..< (start + Int(size)))
  }
}
