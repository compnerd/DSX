// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func handle(event: borrowing Debuggee.Event,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    switch event {
    case .executed, .exited, .forked, .started, .stopped, .terminated:
      return try emit(event, state: &state, writer: &writer)
    case .output(let process):
      try output(process, writer: &writer)
      return .reply
    case .image:
      return .none
    }
  }

  @inline(never)
  internal borrowing func record(_ event: borrowing Debuggee.Event,
                                 state: inout GDBRemoteSessionState)
      throws(GDBHandlerError) {
    // Reserve the Stop: prefix used by the initial notification.
    let capacity = max(0, state.negotiation.payload - 5)
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                      { buffer throws(GDBHandlerError) in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      _ = try emit(event, state: &state, writer: &writer)
      state.stops.record(writer.output.span)
    })
  }

  internal borrowing func snapshot(state: inout GDBRemoteSessionState)
      throws(GDBHandlerError) {
    let current = state.selection.stopped
    if let current, case .stopped(let stop) = debuggee.state(current) {
      try record(.stopped(stop), state: &state)
    }
    for process in debuggee.processes {
      for thread in process.threads where thread.identifier != current {
        if case .stopped(let stop) = thread.state {
          try record(.stopped(stop), state: &state)
        }
      }
    }
  }

  internal mutating func record(_ process: ProcessIdentifier,
                                state: inout GDBRemoteSessionState)
      throws(GDBHandlerError) {
    // Bound the O marker and hex bytes, reserving the Stdio: prefix.
    let limit = 1 + 2 * Configuration.OutputCapacity
    let capacity = min(limit, max(0, state.negotiation.payload - 6))
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                      { buffer throws(GDBHandlerError) in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      try output(process, writer: &writer)
      state.output.record(writer.output.span)
    })
  }
}
