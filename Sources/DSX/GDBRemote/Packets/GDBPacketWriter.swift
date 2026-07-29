// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBPacketWriter: ~Copyable, ~Escapable {
  internal var output: OutputSpan<UInt8>

  @_lifetime(copy output)
  internal init(_ output: consuming OutputSpan<UInt8>) {
    self.output = consume output
  }

  @_lifetime(copy self)
  internal consuming func finish() -> OutputSpan<UInt8> {
    consume output
  }

  internal var count: Int {
    output.count
  }

  internal var capacity: Int {
    output.capacity
  }

  @inline(never)
  internal mutating func append(_ byte: UInt8) throws(GDBHandlerError) {
    guard output.freeCapacity > 0 else {
      throw .capacity
    }
    output.append(byte)
  }

  internal mutating func append(_ value: StaticString) throws(GDBHandlerError) {
    try output.append(value)
  }

  internal mutating func append(_ value: borrowing RegisterText)
      throws(GDBHandlerError) {
    try output.append(value)
  }

  internal mutating func append(_ value: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    try output.append(value)
  }

  internal mutating func hex(_ value: UInt64) throws(GDBHandlerError) {
    var shift = 60
    while shift > 0, value >> shift == 0 {
      shift -= 4
    }
    while shift >= 0 {
      let digit = UInt8(truncatingIfNeeded: value >> shift)
      try append(digit.hexadecimal)
      shift -= 4
    }
  }

  @inline(never)
  internal mutating func hex(_ value: UInt8) throws(GDBHandlerError) {
    guard output.freeCapacity >= 2 else {
      throw .capacity
    }
    output.append((value >> 4).hexadecimal)
    output.append(value.hexadecimal)
  }

  @inline(never)
  internal mutating func decimal(_ value: UInt64) throws(GDBHandlerError) {
    var divisor: UInt64 = 1
    while value / divisor >= 10 {
      divisor *= 10
    }
    while divisor > 0 {
      try append(UInt8(value / divisor % 10) + UInt8(ascii: "0"))
      divisor /= 10
    }
  }

  internal mutating func encoded(_ value: UInt64) throws(GDBHandlerError) {
    var divisor: UInt64 = 1
    while value / divisor >= 10 {
      divisor *= 10
    }
    while divisor > 0 {
      let byte = UInt8(value / divisor % 10) + UInt8(ascii: "0")
      try hex(byte)
      divisor /= 10
    }
  }

  internal mutating func field(_ name: StaticString, decimal value: UInt64)
      throws(GDBHandlerError) {
    try append(name)
    try decimal(value)
    try append(UInt8(ascii: ";"))
  }

  internal mutating func field(_ name: StaticString, hex value: UInt64)
      throws(GDBHandlerError) {
    try append(name)
    try hex(value)
    try append(UInt8(ascii: ";"))
  }

  @inline(never)
  internal mutating func error(_ code: UInt8) throws(GDBHandlerError) {
    guard output.freeCapacity >= 3 else {
      throw .capacity
    }
    output.append(UInt8(ascii: "E"))
    output.append((code >> 4).hexadecimal)
    output.append(code.hexadecimal)
  }

  internal mutating func json(_ value: borrowing String)
      throws(GDBHandlerError) {
    for byte in value.utf8 {
      switch byte {
      case UInt8(ascii: "\""), UInt8(ascii: "\\"):
        try append(UInt8(ascii: "\\"))
        try append(byte)
      case 0x00 ... 0x1f:
        try append("\\u00")
        try hex(byte)
      default:
        try append(byte)
      }
    }
  }
}
