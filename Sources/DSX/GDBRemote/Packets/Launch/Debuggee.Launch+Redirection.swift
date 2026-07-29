// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee.Launch {
  internal mutating func input(_ payload: borrowing Span<UInt8>,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: payload)
    try writer.append("OK")
    input = path
  }

  internal mutating func output(_ payload: borrowing Span<UInt8>,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: payload)
    try writer.append("OK")
    output = path
  }

  internal mutating func error(_ payload: borrowing Span<UInt8>,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: payload)
    try writer.append("OK")
    error = path
  }
}
