// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func nonstop(_ payload: borrowing Span<UInt8>,
                                 state: inout GDBRemoteSessionState,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard payload.count == 1,
        (UInt8(ascii: "0") ... UInt8(ascii: "1")).contains(payload[0]) else {
      throw .malformed
    }
    let enabled = payload[0] == UInt8(ascii: "1")
    try writer.append("OK")
    try translate(mode(enabled, previous: state.nonstop))
    state.nonstop = enabled
    if enabled == false {
      state.stops.reset()
    }
    return .reply
  }
}

extension GDBRemoteSessionState {
  internal mutating func stopped(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard nonstop else {
      throw .code(GDBErrorCode.state)
    }
    try stops.acknowledge(writer: &writer)
  }
}

extension DebugSession {
  internal mutating func interrupt(state: borrowing GDBRemoteSessionState,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard state.nonstop else {
      throw .unsupported
    }
    let selection = state.selection.resume
    let process = try selection.process(in: debuggee)
    _ = try translate(interrupt(process))
    try writer.append("OK")
  }
}

extension GDBRemoteSessionState {
  internal mutating func stdio(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    // A mode change does not acknowledge previously delivered output.
    try output.acknowledge(writer: &writer)
  }
}
