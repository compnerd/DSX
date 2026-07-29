// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBCurrentThreadPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard !session.debuggee.processes.isEmpty else {
      throw .code(GDBErrorCode.process)
    }
    let identifier = GDBPacketScope.thread(state.selection.general,
                                           fallback: state.selection.stopped,
                                           debuggee: session.debuggee)
    guard let identifier, session.debuggee.alive(identifier) else {
      throw .debuggee(.thread)
    }
    try writer.append("QC")
    let multiprocess = state.negotiation.enabled.contains(.multiprocess)
    try writer.thread(identifier, multiprocess: multiprocess)
  }
}

internal enum GDBSelectThreadPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.count > 1 else {
      throw .malformed
    }
    let operation = payload[0]
    let identifier: Debuggee.Thread.Selection
    do throws(GDBHandlerError) {
      identifier = try GDBThreadIdentifier.parse(payload.extracting(1...),
                                                 debuggee: session.debuggee)
    } catch .debuggee {
      throw .code(GDBErrorCode.state)
    } catch {
      throw error
    }
    switch operation {
    case UInt8(ascii: "c"):
      state.selection.resume = identifier
    case UInt8(ascii: "g"):
      state.selection.general = identifier
    default:
      throw .malformed
    }
    try writer.append("OK")
  }
}

internal enum GDBAlivePacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let selection =
        try GDBThreadIdentifier.parse(payload, debuggee: session.debuggee)
    guard case .thread(let identifier) = selection,
        session.debuggee.alive(identifier) else {
      throw .debuggee(.thread)
    }
    try writer.append("OK")
  }
}
