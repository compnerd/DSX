// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBPacketEncoding: UInt8, Sendable {
  case binary
  case text
}

internal enum GDBPacketFrame {
  case control(Range<Int>)
  case packet(Range<Int>)
}

internal enum GDBPacketFraming {
  internal static func extract(_ input: inout MutableSpan<UInt8>,
                               cursor: inout Int,
                               checksum: Bool = true) throws(GDBPacketError)
      -> GDBPacketFrame? {
    guard cursor < input.count else {
      return nil
    }

    let first = input[cursor]
    if first == UInt8(ascii: "+") || first == UInt8(ascii: "-") ||
        first == 0x03 {
      let range = cursor ..< (cursor + 1)
      cursor += 1
      return .control(range)
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
    var index = cursor + 1
    var separator: Int?
    search: while index < input.count {
      let byte = input[index]
      switch (quoted, byte) {
      case (true, _):
        quoted = false
      case (false, UInt8(ascii: "}")):
        if index + 1 < input.count, escape(input[index + 1] ^ 0x20) {
          quoted = true
        }
      case (false, UInt8(ascii: "#")):
        separator = index
        break search
      default:
        break
      }
      index += 1
    }
    guard let separator else {
      return nil
    }
    guard separator + 2 < input.count else {
      return nil
    }
    guard let high = GDBPacketReader.digit(input[separator + 1]),
        let low = GDBPacketReader.digit(input[separator + 2]) else {
      cursor = separator + 3
      throw .malformed
    }

    var actual: UInt8 = 0
    for index in (cursor + 1) ..< separator {
      actual &+= input[index]
    }
    let start = cursor + 1
    cursor = separator + 3
    if checksum {
      guard actual == (high << 4) | low else {
        throw .checksum
      }
    }

    return .packet(start ..< separator)
  }

  internal static func decode(_ range: Range<Int>,
                              input: inout MutableSpan<UInt8>,
                              encoding: GDBPacketEncoding)
      throws(GDBPacketError) -> Range<Int> {
    guard encoding == .binary else {
      return range
    }
    var destination = range.lowerBound
    var index = range.lowerBound
    while index < range.upperBound {
      var byte = input[index]
      if byte == UInt8(ascii: "}") {
        guard index + 1 < range.upperBound,
            escape(input[index + 1] ^ 0x20) else {
          throw .malformed
        }
        index += 1
        byte = input[index] ^ 0x20
      }
      input[destination] = byte
      destination += 1
      index += 1
    }
    return range.lowerBound ..< destination
  }

  internal static func capacity(_ count: Int) -> Int {
    precondition(count <= (Int.max - 4) / 2)
    return count * 2 + 4
  }

  internal static func capacity(_ message: borrowing Span<UInt8>,
                                encoding: GDBPacketEncoding) -> Int {
    var count = 4
    for index in 0 ..< message.count {
      let escaped = encoding == .binary && escape(message[index])
      count += escaped ? 2 : 1
    }
    return count
  }

  internal static func frame(_ message: borrowing Span<UInt8>,
                             encoding: GDBPacketEncoding,
                             output: inout OutputSpan<UInt8>) {
    output.append(UInt8(ascii: "$"))
    var checksum: UInt8 = 0
    for index in 0 ..< message.count {
      let byte = message[index]
      if encoding == .binary, escape(byte) {
        output.append(UInt8(ascii: "}"))
        output.append(byte ^ 0x20)
        checksum &+= UInt8(ascii: "}")
        checksum &+= byte ^ 0x20
      } else {
        output.append(byte)
        checksum &+= byte
      }
    }
    output.append(UInt8(ascii: "#"))
    output.append(GDBPacketWriter.hexadecimal(checksum >> 4))
    output.append(GDBPacketWriter.hexadecimal(checksum))
  }

  internal static func frame(_ count: Int, encoding: GDBPacketEncoding,
                             output: inout MutableSpan<UInt8>) {
    var checksum: UInt8 = 0
    var size = 0
    if count > 0 {
      for index in 0 ..< count {
        let byte = output[index]
        if encoding == .binary, escape(byte) {
          size += 2
          checksum &+= UInt8(ascii: "}")
          checksum &+= byte ^ 0x20
        } else {
          size += 1
          checksum &+= byte
        }
      }
    }

    var source = count
    var destination = size + 1
    while source > 0 {
      source -= 1
      let byte = output[source]
      if encoding == .binary, escape(byte) {
        destination -= 2
        output[destination] = UInt8(ascii: "}")
        output[destination + 1] = byte ^ 0x20
      } else {
        destination -= 1
        output[destination] = byte
      }
    }
    output[0] = UInt8(ascii: "$")
    output[size + 1] = UInt8(ascii: "#")
    output[size + 2] = GDBPacketWriter.hexadecimal(checksum >> 4)
    output[size + 3] = GDBPacketWriter.hexadecimal(checksum)
  }
}

private func escape(_ byte: UInt8) -> Bool {
  byte == UInt8(ascii: "#") || byte == UInt8(ascii: "$") ||
      byte == UInt8(ascii: "}") || byte == UInt8(ascii: "*")
}
