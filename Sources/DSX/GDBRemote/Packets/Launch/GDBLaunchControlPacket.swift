// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBLaunchControlPacket {
  internal static func detach(_ payload: borrowing Span<UInt8>,
                              launch: inout Debuggee.Launch,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.count == 1 else {
      throw .malformed
    }
    switch payload[0] {
    case UInt8(ascii: "0"):
      launch.detach = false
    case UInt8(ascii: "1"):
      launch.detach = true
    default:
      throw .malformed
    }
    try writer.append("OK")
  }
}

extension GDBLaunchControlPacket {
  internal static func terminal(_ payload: borrowing Span<UInt8>,
                                launch: inout Debuggee.Launch,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    var columns: UInt16 = 0
    var rows: UInt16 = 0
    while reader.count > 0 {
      let name = try reader.field(UInt8(ascii: "="))
      let parsed = try reader.decimal()
      guard parsed <= UInt64(UInt16.max) else {
        throw .malformed
      }
      if reader.matches(name, value: "cols") {
        columns = UInt16(parsed)
      }
      if reader.matches(name, value: "rows") {
        rows = UInt16(parsed)
      }
      guard reader.empty || reader.consume(UInt8(ascii: ";")) else {
        throw .malformed
      }
    }
    guard (columns == 0) == (rows == 0) else {
      throw .code(GDBErrorCode.terminal)
    }
    launch.terminal = Debuggee.TerminalSize(columns: columns, rows: rows)
    try writer.append("OK")
  }
}
