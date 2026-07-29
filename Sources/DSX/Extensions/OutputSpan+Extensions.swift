// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension OutputSpan where Element == UInt8 {
  internal mutating func append(_ value: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    guard freeCapacity >= value.count else {
      throw .capacity
    }
    for index in 0 ..< value.count {
      append(value[index])
    }
  }

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
}
