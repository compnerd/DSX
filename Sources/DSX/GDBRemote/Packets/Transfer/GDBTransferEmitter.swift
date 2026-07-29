// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBTransferEmitter {
  private let offset: UInt64
  private let limit: Int
  private var position: UInt64
  private var emitted: Int
  internal private(set) var more: Bool

  internal init(offset: UInt64, limit: Int) {
    self.offset = offset
    self.limit = limit
    position = 0
    emitted = 0
    more = false
  }

  internal mutating func append(_ byte: UInt8,
                                into output: inout OutputSpan<UInt8>) {
    if position >= offset {
      if emitted < limit {
        output.append(byte)
        emitted += 1
      } else {
        more = true
      }
    }
    position &+= 1
  }

  internal mutating func append(_ value: StaticString,
                                into output: inout OutputSpan<UInt8>) {
    value.withUTF8Buffer { value in
      for byte in value {
        append(byte, into: &output)
      }
    }
  }

  internal mutating func append(_ value: borrowing RegisterText,
                                into output: inout OutputSpan<UInt8>) {
    value.bytes { value in
      for index in 0 ..< value.count {
        append(value[index], into: &output)
      }
    }
  }

  internal mutating func append(_ value: borrowing String,
                                into output: inout OutputSpan<UInt8>) {
    for byte in value.utf8 {
      append(byte, into: &output)
    }
  }

  internal mutating func xml(_ value: borrowing String, slash: Bool = false,
                             into output: inout OutputSpan<UInt8>) {
    for byte in value.utf8 {
      switch byte {
      case UInt8(ascii: "&"):
        append("&amp;", into: &output)
      case UInt8(ascii: "\""):
        append("&quot;", into: &output)
      case UInt8(ascii: "'"):
        append("&apos;", into: &output)
      case UInt8(ascii: "<"):
        append("&lt;", into: &output)
      case UInt8(ascii: ">"):
        append("&gt;", into: &output)
      case UInt8(ascii: "\\") where slash:
        append(UInt8(ascii: "/"), into: &output)
      default:
        append(byte, into: &output)
      }
    }
  }

  internal mutating func decimal(_ value: Int,
                                 into output: inout OutputSpan<UInt8>) {
    var divisor = 1
    while value / divisor >= 10 {
      divisor *= 10
    }
    while divisor > 0 {
      append(UInt8(value / divisor % 10) + UInt8(ascii: "0"), into: &output)
      divisor /= 10
    }
  }

  internal mutating func hex(_ value: UInt64,
                             into output: inout OutputSpan<UInt8>) {
    var shift = 60
    while shift > 0, value >> shift == 0 {
      shift -= 4
    }
    while shift >= 0 {
      let digit = UInt8(truncatingIfNeeded: value >> shift)
      append(GDBPacketWriter.hexadecimal(digit), into: &output)
      shift -= 4
    }
  }
}
