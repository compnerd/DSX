// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension MutableSpan where Element == UInt8 {
  internal mutating func decode(_ range: Range<Int>,
                                encoding: GDBPacketEncoding)
      throws(GDBPacketError) -> Range<Int> {
    guard encoding == .binary else {
      return range
    }
    var destination = range.lowerBound
    var index = range.lowerBound
    while index < range.upperBound {
      var byte = self[index]
      if byte == UInt8(ascii: "}") {
        guard index + 1 < range.upperBound,
            GDBPacketEncoding.binary.escapes(self[index + 1] ^ 0x20) else {
          throw .malformed
        }
        index += 1
        byte = self[index] ^ 0x20
      }
      self[destination] = byte
      destination += 1
      index += 1
    }
    return range.lowerBound ..< destination
  }
}
