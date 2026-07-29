// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBSaveCorePacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: borrowing DebugSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let hint = try parse(payload)
    guard let process = session.debuggee.processes.first?.identifier else {
      throw .debuggee(.process)
    }
    let path = try translate(CoreDump.dump(process, hint: hint))
    try writer.append("core-path:")
    for byte in path.utf8 {
      try writer.hex(byte)
    }
  }

  internal static func parse(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) -> String? {
    guard !payload.isEmpty else {
      return nil
    }
    guard payload[0] == UInt8(ascii: ";") else {
      throw .malformed
    }
    var hint: String?
    var start = 1
    while start < payload.count {
      var end = start
      while end < payload.count, payload[end] != UInt8(ascii: ";") {
        end += 1
      }
      var reader = GDBPacketReader(payload.extracting(start ..< end))
      let name = try reader.field(UInt8(ascii: ":"))
      let value = reader.remaining()
      guard reader.matches(name, value: "path-hint") else {
        throw .unsupported
      }
      hint = try GDBPacketReader.string(value)
      start = end + 1
    }
    return hint
  }
}
