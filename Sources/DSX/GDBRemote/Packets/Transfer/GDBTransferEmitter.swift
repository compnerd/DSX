// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBTransferEmitter: ~Copyable, ~Escapable {
  private var output: OutputSpan<UInt8>
  private let offset: UInt64
  private let limit: Int
  private var position: UInt64
  internal private(set) var more: Bool

  @_lifetime(copy output)
  internal init(_ output: consuming OutputSpan<UInt8>, offset: UInt64,
                limit: Int) {
    self.offset = offset
    self.limit = output.count + limit
    self.output = consume output
    position = 0
    more = false
  }

  @_lifetime(copy self)
  internal consuming func finish() -> OutputSpan<UInt8> {
    consume output
  }

  internal mutating func append(_ byte: UInt8) {
    if position >= offset {
      if output.count < limit {
        output.append(byte)
      } else {
        more = true
      }
    }
    position &+= 1
  }

  internal mutating func append(_ value: StaticString) {
    value.withUTF8Buffer { value in
      for byte in value {
        append(byte)
      }
    }
  }

  internal mutating func append(_ value: borrowing RegisterText) {
    value.bytes { value in
      for index in 0 ..< value.count {
        append(value[index])
      }
    }
  }

  internal mutating func append(_ value: borrowing String) {
    for byte in value.utf8 {
      append(byte)
    }
  }

  internal mutating func xml(_ value: borrowing String,
                             separator: UInt8 = UInt8(ascii: "/"))
      throws(Debuggee.Error) {
    var prefix: UInt16 = 0
    for byte in value.utf8 {
      // String is valid UTF-8. XML additionally excludes U+FFFE and U+FFFF.
      if prefix == 0xefbf, byte >= 0xbe {
        throw .state
      }
      prefix = prefix << 8 | UInt16(byte)
      try xml(byte == separator ? UInt8(ascii: "/") : byte)
    }
  }

  private mutating func xml(_ byte: UInt8) throws(Debuggee.Error) {
    let escaped: StaticString? = switch byte {
    case 0x09: "&#9;"
    case 0x0a: "&#10;"
    case 0x0d: "&#13;"
    case 0x00 ... 0x1f: throw .state
    case UInt8(ascii: "&"): "&amp;"
    case UInt8(ascii: "\""): "&quot;"
    case UInt8(ascii: "'"): "&apos;"
    case UInt8(ascii: "<"): "&lt;"
    case UInt8(ascii: ">"): "&gt;"
    default: nil
    }
    if let escaped {
      append(escaped)
    } else {
      append(byte)
    }
  }

  internal mutating func decimal(_ value: Int) {
    var divisor = 1
    while value / divisor >= 10 {
      divisor *= 10
    }
    while divisor > 0 {
      append(UInt8(value / divisor % 10) + UInt8(ascii: "0"))
      divisor /= 10
    }
  }

  internal mutating func hex(_ value: UInt64) {
    var shift = 60
    while shift > 0, value >> shift == 0 {
      shift -= 4
    }
    while shift >= 0 {
      let digit = UInt8(truncatingIfNeeded: value >> shift)
      append(digit.hexadecimal)
      shift -= 4
    }
  }
}

extension GDBTransferEmitter {
  internal mutating func path(_ value: borrowing String)
      throws(Debuggee.Error) {
    try xml(value, separator: NativeFileSystem.separator)
  }
}
