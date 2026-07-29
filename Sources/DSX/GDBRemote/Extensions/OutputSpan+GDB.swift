// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension OutputSpan where Element == UInt8 {
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
