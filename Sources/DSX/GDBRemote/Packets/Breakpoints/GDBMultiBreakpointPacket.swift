// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBMultiBreakpointPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    var reader = GDBPacketReader(payload.extracting(0...))
    reader.whitespace()
    guard reader.consume(UInt8(ascii: "{")) else {
      throw .malformed
    }
    reader.whitespace()
    guard reader.consume("\"breakpoint_requests\"") else {
      throw .malformed
    }
    reader.whitespace()
    guard reader.consume(UInt8(ascii: ":")) else {
      throw .malformed
    }
    reader.whitespace()
    guard reader.consume(UInt8(ascii: "[")) else {
      throw .malformed
    }
    try writer.append("{\"results\":[")
    var first = true
    while true {
      reader.whitespace()
      if reader.consume(UInt8(ascii: "]")) {
        break
      }
      guard first || reader.consume(UInt8(ascii: ",")) else {
        throw .malformed
      }
      reader.whitespace()
      guard reader.consume(UInt8(ascii: "\"")) else {
        throw .malformed
      }
      let request = try reader.field(UInt8(ascii: "\""))
      if first {
        first = false
      } else {
        try writer.append(UInt8(ascii: ","))
      }
      try result(reader.span(request), session: &session, state: state,
                 writer: &writer)
    }
    reader.whitespace()
    guard reader.consume(UInt8(ascii: "}")) else {
      throw .malformed
    }
    reader.whitespace()
    guard reader.empty else {
      throw .malformed
    }
    try writer.append("]}")
    return .reply
  }
}

private func result(_ request: borrowing Span<UInt8>,
                    session: inout DebugSession,
                    state: borrowing GDBRemoteSessionState,
                    writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  do throws(GDBHandlerError) {
    guard request.count > 1 else {
      throw .malformed
    }
    let site = try GDBBreakpointPacket.parse(request.extracting(1...))
    switch request[0] {
    case UInt8(ascii: "Z"):
      try GDBBreakpointPacket.insert(site, session: &session, state: state)
    case UInt8(ascii: "z"):
      guard try GDBBreakpointPacket.remove(site, session: &session,
                                           state: state) else {
        throw .code(GDBErrorCode.invalid)
      }
    default:
      throw .malformed
    }
    try writer.append("\"OK\"")
  } catch .capacity {
    throw .capacity
  } catch .code(let code) {
    try failure(code, writer: &writer)
  } catch .debuggee(.access) {
    try failure(GDBErrorCode.access, writer: &writer)
  } catch {
    try failure(GDBErrorCode.invalid, writer: &writer)
  }
}

private func failure(_ code: UInt8, writer: inout GDBPacketWriter)
    throws(GDBHandlerError) {
  try writer.append(UInt8(ascii: "\""))
  try writer.error(code)
  try writer.append(UInt8(ascii: "\""))
}

extension GDBPacketReader {
  fileprivate mutating func whitespace() {
    while true {
      switch try? read() {
      case UInt8(ascii: " "), UInt8(ascii: "\t"),
           UInt8(ascii: "\n"), UInt8(ascii: "\r"):
        continue
      case .some:
        rewind()
      case .none:
        break
      }
      return
    }
  }
}
