// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  @inline(__always)
  internal borrowing func current(_ payload: borrowing Span<UInt8>,
                                  state: borrowing GDBRemoteSessionState,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard !processes.isEmpty else {
      throw .code(GDBErrorCode.process)
    }
    let identifier = state.selection.resolve(in: self)
    guard let identifier, alive(identifier) else {
      throw .debuggee(.thread)
    }
    try writer.append("QC")
    let multiprocess = state.negotiation.enabled.contains(.multiprocess)
    try writer.thread(identifier, multiprocess: multiprocess)
  }
}

extension DebugSession {
  internal borrowing func select(_ payload: borrowing Span<UInt8>,
                                 state: inout GDBRemoteSessionState,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.count > 1 else {
      throw .malformed
    }
    let operation = payload[0]
    let identifier: Debuggee.Thread.Selection
    do throws(GDBHandlerError) {
      identifier = try Debuggee.Thread.Selection(payload.extracting(1...),
                                                 debuggee: debuggee)
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

extension Debuggee {
  @inline(__always)
  internal borrowing func alive(_ payload: borrowing Span<UInt8>,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let selection = try Debuggee.Thread.Selection(payload, debuggee: self)
    guard case .thread(let identifier) = selection, alive(identifier) else {
      throw .debuggee(.thread)
    }
    try writer.append("OK")
  }
}
