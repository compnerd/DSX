// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func watchpoints(_ payload: borrowing Span<UInt8>,
                                     state: borrowing GDBRemoteSessionState,
                                     writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    let process: ProcessIdentifier? = if debuggee.processes.isEmpty {
      nil
    } else {
      try state.selection.general.process(in: debuggee)
    }
    return if let count = try translate(watchpoints(process)) {
      try writer.watchpoints(count)
    } else {
      try writer.append("OK")
    }
  }

}

extension GDBPacketWriter {
  internal mutating func watchpoints(_ count: Int) throws(GDBHandlerError) {
    guard count >= 0 else {
      throw .debuggee(.breakpoint)
    }
    try field("num:", decimal: UInt64(count))
  }
}
