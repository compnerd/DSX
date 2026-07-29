// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum ModuleIdentifier {
  internal static func checksum(_ bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> String {
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
    return encode(value)
  }

  internal static func encode(_ value: UInt32) -> String {
    var identifier = String()
    identifier.reserveCapacity(8)
    for index in 0 ..< 4 {
      append(UInt8(truncatingIfNeeded: value >> UInt32(index * 8)),
             to: &identifier)
    }
    return identifier
  }

  internal static func append(_ value: UInt8, to string: inout String) {
    string.append(Character(UnicodeScalar(hex(value >> 4))))
    string.append(Character(UnicodeScalar(hex(value))))
  }
}

private func hex(_ value: UInt8) -> UInt8 {
  let digit = value & 0x0f
  return digit < 10 ? digit + UInt8(ascii: "0")
      : digit - 10 + UInt8(ascii: "A")
}
