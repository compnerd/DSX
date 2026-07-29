// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBSyscallPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let calls: Array<UInt64>?
    switch try reader.read() {
    case UInt8(ascii: "0"):
      guard reader.empty else {
        throw .malformed
      }
      calls = nil
    case UInt8(ascii: "1"):
      var selected = Array<UInt64>()
      while reader.consume(UInt8(ascii: ";")) {
        try selected.append(reader.hex())
      }
      guard reader.empty else {
        throw .malformed
      }
      calls = selected
    default: throw .malformed
    }
    try translate(session.syscalls(calls))
    try writer.append("OK")
  }
}
