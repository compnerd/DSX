// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBPacketReader: ~Escapable {
  private let packet: Span<UInt8>
  internal private(set) var index: Int

  @_lifetime(copy packet)
  internal init(_ packet: consuming Span<UInt8>) {
    self.packet = consume packet
    index = 0
  }

  internal var empty: Bool {
    index == packet.count
  }

  internal var count: Int {
    packet.count - index
  }

  internal mutating func consume(_ byte: UInt8) -> Bool {
    guard index < packet.count, packet[index] == byte else {
      return false
    }
    index += 1
    return true
  }

  @inline(never)
  internal mutating func consume(_ value: StaticString) -> Bool {
    guard value.utf8CodeUnitCount <= count else {
      return false
    }
    let matches = value.withUTF8Buffer { value in
      for offset in 0 ..< value.count {
        guard packet[index + offset] == value[offset] else {
          return false
        }
      }
      return true
    }
    guard matches else {
      return false
    }
    index += value.utf8CodeUnitCount
    return true
  }

  internal mutating func read() throws(GDBHandlerError) -> UInt8 {
    guard index < packet.count else {
      throw .malformed
    }
    let byte = packet[index]
    index += 1
    return byte
  }

  internal mutating func rewind() {
    precondition(index > 0)
    index -= 1
  }

  @inline(never)
  internal mutating func hex() throws(GDBHandlerError) -> UInt64 {
    var value: UInt64 = 0
    var consumed = false
    while index < packet.count, let digit = UInt8(hex: packet[index]) {
      guard value <= (UInt64.max - UInt64(digit)) / 16 else {
        throw .malformed
      }
      value = value * 16 + UInt64(digit)
      index += 1
      consumed = true
    }
    guard consumed else {
      throw .malformed
    }
    return value
  }

  internal mutating func decimal() throws(GDBHandlerError) -> UInt64 {
    var value: UInt64 = 0
    var consumed = false
    while index < packet.count,
        (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(packet[index]) {
      let digit = UInt64(packet[index] - UInt8(ascii: "0"))
      guard value <= (UInt64.max - digit) / 10 else {
        throw .malformed
      }
      value = value * 10 + digit
      index += 1
      consumed = true
    }
    guard consumed else {
      throw .malformed
    }
    return value
  }

  internal mutating func skip(_ delimiter: UInt8) {
    while index < packet.count {
      guard packet[index] == delimiter else {
        index += 1
        continue
      }
      return
    }
  }

  internal mutating func field(_ delimiter: UInt8) throws(GDBHandlerError)
      -> Range<Int> {
    let range = prefix(delimiter)
    guard consume(delimiter) else {
      throw .malformed
    }
    return range
  }

  internal mutating func prefix(_ delimiter: UInt8) -> Range<Int> {
    let start = index
    skip(delimiter)
    return start ..< index
  }

  internal mutating func take(_ count: Int) throws(GDBHandlerError)
      -> Range<Int> {
    guard count >= 0, count <= self.count else {
      throw .malformed
    }
    let range = index ..< (index + count)
    index += count
    return range
  }

  @inline(never)
  internal borrowing func matches(_ range: Range<Int>,
                                  value: StaticString) -> Bool {
    guard range.count == value.utf8CodeUnitCount else {
      return false
    }
    return value.withUTF8Buffer { value in
      for offset in 0 ..< value.count {
        guard packet[range.lowerBound + offset] == value[offset] else {
          return false
        }
      }
      return true
    }
  }

  @_lifetime(copy self)
  internal borrowing func span(_ range: Range<Int>) -> Span<UInt8> {
    packet.extracting(range)
  }

  @_lifetime(copy self)
  internal borrowing func remaining() -> Span<UInt8> {
    packet.extracting(index...)
  }
}
