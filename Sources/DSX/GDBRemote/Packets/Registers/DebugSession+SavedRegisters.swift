// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal borrowing func sync(_ payload: borrowing Span<UInt8>,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    guard reader.consume(UInt8(ascii: ":")) else {
      throw .malformed
    }
    let selection =
        try Debuggee.Thread.Selection(reader.remaining(), debuggee: debuggee)
    guard case .thread(let thread) = selection else {
      throw .debuggee(.thread)
    }
    try translate(NativeRegisterState.synchronize(thread))
    try writer.append("OK")
  }

  internal mutating func save(_ payload: borrowing Span<UInt8>,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let thread = try saved(payload, state: state)
    let identifier = try translate(save(thread))
    try writer.decimal(identifier)
  }

  internal mutating func restore(_ payload: borrowing Span<UInt8>,
                                 state: borrowing GDBRemoteSessionState,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let identifier = try reader.decimal()
    let thread =
        try reader.empty ? nil : saved(reader.remaining(), state: state)
    do {
      try restore(identifier, thread: thread)
    } catch {
      error.log("failed to restore register state")
      throw .debuggee(error)
    }
    try writer.append("OK")
  }

  private borrowing func saved(_ payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) -> ProcessThreadIdentifier {
    if payload.count == 0 {
      let selected = debuggee.resolve(state.selection.general)
      if let selected {
        return selected
      }
      if let stopped = state.selection.stopped {
        return stopped
      }
      throw .debuggee(.thread)
    }
    var reader = GDBPacketReader(payload.extracting(0...))
    _ = reader.consume(UInt8(ascii: ";"))
    guard reader.consume("thread:") else {
      throw .malformed
    }
    let field = reader.prefix(UInt8(ascii: ";"))
    let selection =
        try Debuggee.Thread.Selection(reader.span(field), debuggee: debuggee)
    _ = reader.consume(UInt8(ascii: ";"))
    guard reader.empty else {
      throw .malformed
    }
    guard case .thread(let thread) = selection else {
      throw .debuggee(.thread)
    }
    return thread
  }
}
