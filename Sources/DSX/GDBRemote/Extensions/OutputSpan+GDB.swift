// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension OutputSpan where Element == UInt8 {
  @inline(never)
  internal mutating func append(_ value: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    guard freeCapacity >= value.count else {
      throw .capacity
    }
    for index in 0 ..< value.count {
      append(value[index])
    }
  }

  @inline(never)
  internal mutating func append(_ value: StaticString) throws(GDBHandlerError) {
    guard freeCapacity >= value.utf8CodeUnitCount else {
      throw .capacity
    }
    value.withUTF8Buffer { value in
      for byte in value {
        append(byte)
      }
    }
  }

  internal mutating func append(_ value: borrowing RegisterText)
      throws(GDBHandlerError) {
    guard freeCapacity >= value.count else {
      throw .capacity
    }
    value.bytes { value in
      for index in 0 ..< value.count {
        append(value[index])
      }
    }
  }

  internal mutating func decode(_ input: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    guard input.count % 2 == 0, freeCapacity >= input.count / 2 else {
      throw .malformed
    }
    var index = 0
    while index < input.count {
      guard let high = UInt8(hex: input[index]),
          let low = UInt8(hex: input[index + 1]) else {
        throw .malformed
      }
      append(high << 4 | low)
      index += 2
    }
  }
}
