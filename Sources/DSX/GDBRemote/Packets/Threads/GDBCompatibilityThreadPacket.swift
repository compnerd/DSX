// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  @inline(__always)
  internal borrowing func stopped(_ payload: borrowing Span<UInt8>,
                                  state: borrowing GDBRemoteSessionState,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let selection = try Debuggee.Thread.Selection(payload, debuggee: debuggee)
    guard case .thread(let identifier) = selection,
        let thread = debuggee.state(identifier) else {
      throw .debuggee(.thread)
    }
    let reply = switch thread {
    case .stopped(let stop): (stop, true)
    case .running, .stepping:
      (Debuggee.Stop(thread: identifier, reason: .signal(0)), false)
    case .terminated: throw .debuggee(.thread)
    }
    try emit(reply.0, state: state, writer: &writer, registers: reply.1)
    return .reply
  }
}

extension Debuggee {
  internal borrowing func thread(_ payload: borrowing Span<UInt8>,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let selection = try Debuggee.Thread.Selection(payload, debuggee: self)
    guard case .thread(let thread) = selection else {
      throw .debuggee(.thread)
    }
    let info = try translate(thread.info)
    let name = info.name ?? "thread \(thread.thread.rawValue)"
    try writer.encoded(name)
  }
}

extension DebugSession {
  internal borrowing func threads(_ payload: borrowing Span<UInt8>,
                                  state: borrowing GDBRemoteSessionState,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try writer.emit(threads: self, state: state)
    return .reply
  }
}
