// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBPacketEncoding: UInt8, Sendable {
  case binary
  case text

  internal func escapes(_ byte: UInt8) -> Bool {
    guard self == .binary else {
      return false
    }
    return byte == UInt8(ascii: "#") || byte == UInt8(ascii: "$") ||
        byte == UInt8(ascii: "}") || byte == UInt8(ascii: "*")
  }
}

internal enum GDBPacketFrame {
  case control(Range<Int>)
  case packet(Range<Int>)

  internal init?(_ input: borrowing Span<UInt8>, cursor: inout Int,
                 checksum: Bool = true) throws(GDBPacketError) {
    guard cursor < input.count else {
      return nil
    }

    let first = input[cursor]
    if first == UInt8(ascii: "+") || first == UInt8(ascii: "-") ||
        first == 0x03 {
      let range = cursor ..< (cursor + 1)
      cursor += 1
      self = .control(range)
      return
    }
    guard first == UInt8(ascii: "$") else {
      cursor += 1
      while cursor < input.count {
        let byte = input[cursor]
        if byte == UInt8(ascii: "$") || byte == UInt8(ascii: "+") ||
            byte == UInt8(ascii: "-") || byte == 0x03 {
          break
        }
        cursor += 1
      }
      throw .malformed
    }

    var quoted = false
    var actual: UInt8 = 0
    var index = cursor + 1
    var separator: Int?
    search: while index < input.count {
      let byte = input[index]
      switch (quoted, byte) {
      case (true, _):
        quoted = false
      case (false, UInt8(ascii: "}")):
        if index + 1 < input.count,
            GDBPacketEncoding.binary.escapes(input[index + 1] ^ 0x20) {
          quoted = true
        }
      case (false, UInt8(ascii: "#")):
        separator = index
        break search
      default:
        break
      }
      actual &+= byte
      index += 1
    }
    guard let separator else {
      return nil
    }
    guard separator + 2 < input.count else {
      return nil
    }
    guard let high = UInt8(hex: input[separator + 1]),
        let low = UInt8(hex: input[separator + 2]) else {
      cursor = separator + 3
      throw .malformed
    }

    let start = cursor + 1
    cursor = separator + 3
    if checksum {
      guard actual == (high << 4) | low else {
        throw .checksum
      }
    }

    self = .packet(start ..< separator)
  }
}

extension GDBPacketEncoding {
  /// Framed capacity for a payload whose contents are not yet available.
  @inline(__always)
  internal func capacity(_ count: Int) -> Int {
    precondition(count <= (Int.max - 4) / 2)
    return (self == .binary ? count * 2 : count) + 4
  }

  internal func capacity(_ message: borrowing Span<UInt8>) -> Int {
    var count = message.count + 4
    if self == .binary {
      for index in 0 ..< message.count where escapes(message[index]) {
        count += 1
      }
    }
    return count
  }
}
