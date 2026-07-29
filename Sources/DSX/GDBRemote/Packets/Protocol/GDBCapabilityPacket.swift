// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBCapabilityPacket {
  internal static func handle(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append("OK")
  }
}

internal enum GDBWatchpointPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    let process: ProcessIdentifier? = if session.debuggee.processes.isEmpty {
      nil
    } else {
      try GDBPacketScope.process(state.selection.general,
                                 debuggee: session.debuggee)
    }
    return if let count = try translate(session.watchpoints(process)) {
      try handle(count, writer: &writer)
    } else {
      try writer.append("OK")
    }
  }

  internal static func handle(_ count: Int, writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard count >= 0 else {
      throw .debuggee(.breakpoint)
    }
    try writer.field("num:", decimal: UInt64(count))
  }
}
