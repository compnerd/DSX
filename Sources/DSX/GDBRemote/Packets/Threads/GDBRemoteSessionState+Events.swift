// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemoteSessionState {
  internal mutating func events(_ payload: borrowing Span<UInt8>,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard negotiation.supported.contains(.events) else {
      throw .unsupported
    }
    guard payload.count == 1 else {
      throw .malformed
    }
    switch payload[0] {
    case UInt8(ascii: "0"):
      events = false
    case UInt8(ascii: "1"):
      events = true
    default:
      throw .malformed
    }
    try writer.append("OK")
  }

  internal mutating func options(_ payload: borrowing Span<UInt8>,
                                 session: borrowing DebugSession,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard negotiation.supported.contains(.options) else {
      throw .unsupported
    }
    var reader = GDBPacketReader(payload.extracting(0...))
    if reader.empty {
      throw .malformed
    }
    while reader.consume(UInt8(ascii: ";")) {
      let options = try reader.hex()
      guard options & 0x02 == options else {
        throw .unsupported
      }
      let separator = UInt8(ascii: ":")
      let field: Range<Int>? = if reader.consume(separator) {
        reader.prefix(UInt8(ascii: ";"))
      } else {
        nil
      }
      let selection: Debuggee.Thread.Selection = if let field {
        try Debuggee.Thread.Selection(reader.span(field),
                                      debuggee: session.debuggee)
      } else {
        .all
      }
      self.options.set(selection, options: options, debuggee: session.debuggee)
    }
    guard reader.empty else {
      throw .malformed
    }
    try writer.append("OK")
  }
}
