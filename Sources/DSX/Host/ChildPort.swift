// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct ChildPort {
  private var value: UInt64 = 0
  private var count = 0

  internal mutating func consume(_ byte: UInt8) throws(Debuggee.Error)
      -> UInt16? {
    if byte == UInt8(ascii: "\n") {
      guard count > 0, value <= UInt64(UInt16.max) else {
        throw .state
      }
      return UInt16(value)
    }
    guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9"), count < 5 else {
      throw .state
    }
    value = value * 10 + UInt64(byte - UInt8(ascii: "0"))
    count += 1
    return nil
  }
}
