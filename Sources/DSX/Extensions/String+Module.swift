// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension String {
  internal init(uuid bytes: borrowing Span<UInt8>) {
    precondition(bytes.count == 16)
    self.init()
    reserveCapacity(36)
    for index in 0 ..< bytes.count {
      if index == 4 || index == 6 || index == 8 || index == 10 {
        append("-")
      }
      append(hex: bytes[index])
    }
  }

  internal init(digest bytes: borrowing Span<UInt8>) {
    self.init()
    reserveCapacity(bytes.count * 2)
    for index in 0 ..< bytes.count {
      append(hex: bytes[index])
    }
  }

  internal init(checksum bytes: borrowing Span<UInt8>) throws(Debuggee.Error) {
    var value = UInt32.max
    for index in 0 ..< bytes.count {
      value ^= UInt32(bytes[index])
      for _ in 0 ..< 8 {
        let mask = UInt32(bitPattern: -Int32(value & 1))
        value = value >> 1 ^ (0xedb8_8320 & mask)
      }
    }
    value = ~value
    guard value > 0 else {
      throw .process
    }
    self.init(checksum: value)
  }

  internal init(debuglink bytes: borrowing Span<UInt8>, little: Bool = true)
      throws(Debuggee.Error) {
    var end = 0
    while end < bytes.count, bytes[end] != 0 {
      end += 1
    }
    guard end < bytes.count, end <= Int.max - 4 else {
      throw .process
    }
    let offset = (end + 4) & ~3
    let value = try bytes.integer(at: offset, count: 4, little: little)
    self.init(checksum: UInt32(value))
  }

  internal init(checksum value: UInt32) {
    self.init()
    reserveCapacity(8)
    for index in 0 ..< 4 {
      append(hex: UInt8(truncatingIfNeeded: value >> UInt32(index * 8)))
    }
  }

  internal mutating func append(hex value: UInt8) {
    append(Character(UnicodeScalar(hex(value >> 4))))
    append(Character(UnicodeScalar(hex(value))))
  }
}

private func hex(_ value: UInt8) -> UInt8 {
  let digit = value & 0x0f
  return digit < 10 ? digit + UInt8(ascii: "0")
      : digit - 10 + UInt8(ascii: "A")
}
