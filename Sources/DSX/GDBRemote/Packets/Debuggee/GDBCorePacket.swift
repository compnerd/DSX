// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal borrowing func core(_ payload: borrowing Span<UInt8>,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let hint = try GDBPacketReader(payload.extracting(0...)).hint()
    guard let process = debuggee.processes.first?.identifier else {
      throw .debuggee(.process)
    }
    let path = try translate(CoreDump.dump(process, hint: hint))
    try writer.append("core-path:")
    try writer.encoded(path)
  }

}

extension GDBPacketReader {
  internal borrowing func hint() throws(GDBHandlerError) -> String? {
    let payload = remaining()
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
      hint = try String(hex: value)
      start = end + 1
    }
    return hint
  }
}
