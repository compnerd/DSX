// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func encoded(_ value: borrowing String)
      throws(GDBHandlerError) {
    guard output.freeCapacity >= value.utf8.count * 2 else {
      throw .capacity
    }
    for byte in value.utf8 {
      try hex(byte)
    }
  }

  internal mutating func encoded(_ value: StaticString)
      throws(GDBHandlerError) {
    guard output.freeCapacity >= value.utf8CodeUnitCount * 2 else {
      throw .capacity
    }
    value.withUTF8Buffer { buffer in
      for byte in buffer {
        output.append((byte >> 4).hexadecimal)
        output.append(byte.hexadecimal)
      }
    }
  }
}
