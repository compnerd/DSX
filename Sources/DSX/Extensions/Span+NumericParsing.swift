// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal func integer(_ bytes: borrowing Span<UInt8>, at offset: Int,
                      count: Int) throws(Debuggee.Error) -> UInt64 {
  guard offset >= 0, count > 0, count <= 8, offset <= bytes.count,
      count <= bytes.count - offset else {
    throw .process
  }
  var value: UInt64 = 0
  for index in 0 ..< count {
    value |= UInt64(bytes[offset + index]) << UInt64(index * 8)
  }
  return value
}

internal func integer(_ bytes: borrowing Span<UInt8>, at offset: Int,
                      count: Int, little: Bool)
    throws(Debuggee.Error) -> UInt64 {
  if little {
    return try integer(bytes, at: offset, count: count)
  }
  guard offset >= 0, count > 0, count <= 8, offset <= bytes.count,
      count <= bytes.count - offset else {
    throw .process
  }
  var value: UInt64 = 0
  for index in 0 ..< count {
    value = value << 8 | UInt64(bytes[offset + index])
  }
  return value
}

internal func decimal(_ bytes: borrowing Span<UInt8>,
                      limit: UInt64 = UInt64.max) -> UInt64? {
  guard !bytes.isEmpty else {
    return nil
  }
  var value: UInt64 = 0
  for index in 0 ..< bytes.count {
    let byte = bytes[index]
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
