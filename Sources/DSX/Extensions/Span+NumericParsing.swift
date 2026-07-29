// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Span where Element == UInt8 {
  @inline(__always)
  internal func integer(at offset: Int, count length: Int)
      throws(Debuggee.Error) -> UInt64 {
    try integer(at: offset, count: length, little: true)
  }

  @inline(__always)
  internal func integer(at offset: Int, count length: Int, little: Bool)
      throws(Debuggee.Error) -> UInt64 {
    guard offset >= 0, length > 0, length <= 8, offset <= count,
        length <= count - offset else {
      throw .process
    }
    var value: UInt64 = 0
    for index in 0 ..< length {
      let shift = little ? index : length - index - 1
      value |= UInt64(self[offset + index]) << UInt64(shift * 8)
    }
    return value
  }

  internal func decimal(limit: UInt64 = UInt64.max) -> UInt64? {
    guard !isEmpty else {
      return nil
    }
    var value: UInt64 = 0
    for index in 0 ..< count {
      let byte = self[index]
      guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
        return nil
      }
      let digit = UInt64(byte - UInt8(ascii: "0"))
      guard digit <= limit, value <= (limit - digit) / 10 else {
        return nil
      }
      value = value * 10 + digit
    }
    return value
  }
}
