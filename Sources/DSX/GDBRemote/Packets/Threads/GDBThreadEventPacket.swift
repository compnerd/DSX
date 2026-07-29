// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBThreadEventPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard state.negotiation.supported.contains(.events) else {
      throw .unsupported
    }
    guard payload.count == 1 else {
      throw .malformed
    }
    switch payload[0] {
    case UInt8(ascii: "0"):
      state.events = false
    case UInt8(ascii: "1"):
      state.events = true
    default:
      throw .malformed
    }
    try writer.append("OK")
  }
}

internal enum GDBThreadOptionPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: borrowing DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard state.negotiation.supported.contains(.options) else {
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
        try GDBThreadIdentifier.parse(reader.span(field),
                                      debuggee: session.debuggee)
      } else {
        .all
      }
      state.options.set(selection, options: options, debuggee: session.debuggee)
    }
    guard reader.empty else {
      throw .malformed
    }
    try writer.append("OK")
  }
}
