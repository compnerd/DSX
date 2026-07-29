// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketReader {
  @inline(never)
  internal mutating func quoted() throws(GDBHandlerError) -> Range<Int> {
    guard consume(UInt8(ascii: "\"")) else {
      throw .malformed
    }
    let start = index
    while empty == false {
      let byte = try read()
      if byte == UInt8(ascii: "\"") {
        return start ..< index - 1
      }
      guard byte >= UInt8(ascii: " ") else {
        throw .malformed
      }
      guard byte == UInt8(ascii: "\\") else {
        continue
      }
      _ = try escape()
    }
    throw .malformed
  }

  internal borrowing func json(_ range: Range<Int>) throws(GDBHandlerError)
      -> String {
    let bytes = span(range)
    var escape = false
    for index in 0 ..< bytes.count where bytes[index] == UInt8(ascii: "\\") {
      escape = true
      break
    }
    guard escape else {
      return String(decoding: bytes, as: UTF8.self)
    }
    let capacity = bytes.count
    let result = withUnsafeTemporaryAllocation(of: UInt8.self,
                                               capacity: capacity) { buffer in
      buffer.unescape(bytes)
    }
    return try result.get()
  }

  @inline(never)
  internal mutating func token(_ byte: UInt8) -> Bool {
    whitespace()
    guard consume(byte) else {
      return false
    }
    whitespace()
    return true
  }

  private mutating func whitespace() {
    while consume(UInt8(ascii: "\t")) || consume(UInt8(ascii: "\n")) ||
          consume(UInt8(ascii: "\r")) || consume(UInt8(ascii: " ")) {
    }
  }

  fileprivate mutating func escape() throws(GDBHandlerError) -> Unicode.Scalar {
    let byte = try read()
    if let byte = byte.unescaped {
      return Unicode.Scalar(byte)
    }
    guard byte == UInt8(ascii: "u") else {
      throw .malformed
    }
    let first = try unit()
    if (0xd800 ... 0xdbff).contains(first) {
      guard consume(UInt8(ascii: "\\")), consume(UInt8(ascii: "u")) else {
        throw .malformed
      }
      let second = try unit()
      guard (0xdc00 ... 0xdfff).contains(second) else {
        throw .malformed
      }
      let value = 0x10000 + ((first - 0xd800) << 10) + second - 0xdc00
      return Unicode.Scalar(value)!
    }
    guard let scalar = Unicode.Scalar(first) else {
      throw .malformed
    }
    return scalar
  }

  private mutating func unit() throws(GDBHandlerError) -> UInt32 {
    let range = try take(4)
    var reader = GDBPacketReader(span(range))
    let value = try reader.hex()
    guard reader.empty else {
      throw .malformed
    }
    return UInt32(value)
  }
}

extension UnsafeMutableBufferPointer where Element == UInt8 {
  fileprivate func unescape(_ bytes: borrowing Span<UInt8>)
      -> Result<String, GDBHandlerError> {
    var decoded = OutputSpan(buffer: self, initializedCount: 0)
    var reader = GDBPacketReader(bytes.extracting(0...))
    do {
      while reader.empty == false {
        let byte = try reader.read()
        if byte == UInt8(ascii: "\\") {
          let scalar = try reader.escape()
          UTF8.encode(scalar) { decoded.append($0) }
        } else {
          decoded.append(byte)
        }
      }
    } catch {
      return .failure(error)
    }
    let value = String(decoding: decoded.span, as: UTF8.self)
    return .success(value)
  }
}

extension UInt8 {
  fileprivate var unescaped: UInt8? {
    switch self {
    case UInt8(ascii: "\""), UInt8(ascii: "/"), UInt8(ascii: "\\"): self
    case UInt8(ascii: "b"): 0x08
    case UInt8(ascii: "f"): 0x0c
    case UInt8(ascii: "n"): 0x0a
    case UInt8(ascii: "r"): 0x0d
    case UInt8(ascii: "t"): 0x09
    default: nil
    }
  }
}
