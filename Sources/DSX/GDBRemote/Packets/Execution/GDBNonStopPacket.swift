// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBNonStopPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard payload.count == 1,
        (UInt8(ascii: "0") ... UInt8(ascii: "1")).contains(payload[0]) else {
      throw .malformed
    }
    let enabled = payload[0] == UInt8(ascii: "1")
    try translate(session.mode(enabled, previous: state.nonstop))
    state.nonstop = enabled
    if enabled == false {
      state.stops.reset()
    }
    try writer.append("OK")
    return .reply
  }
}

extension GDBNonStopPacket {
  internal static func status(_ payload: borrowing Span<UInt8>,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard state.nonstop else {
      throw .code(GDBErrorCode.state)
    }
    if state.stops.first == nil {
      throw .code(GDBErrorCode.state)
    }
    guard let reply = state.stops.next() else {
      return try writer.append("OK")
    }
    try writer.append(reply.span)
  }
}

extension GDBNonStopPacket {
  internal static func interrupt(_ payload: borrowing Span<UInt8>,
                                 session: inout DebugSession,
                                 state: inout GDBRemoteSessionState,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard state.nonstop else {
      throw .unsupported
    }
    let selection = state.selection.resume
    let process =
        try GDBPacketScope.process(selection, debuggee: session.debuggee)
    _ = try translate(session.interrupt(process))
    try writer.append("OK")
  }
}

extension GDBNonStopPacket {
  internal static func stdio(_ payload: borrowing Span<UInt8>,
                             state: inout GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard state.nonstop else {
      throw .unsupported
    }
    try writer.append("OK")
  }
}
