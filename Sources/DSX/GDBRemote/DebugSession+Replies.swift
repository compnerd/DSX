// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func handle(event: borrowing Debuggee.Event,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    switch event {
    case .executed, .exited, .forked, .started, .stopped, .terminated:
      return try GDBStopPacket.write(event, session: &self, state: &state,
                                     writer: &writer)
    case .output(let process):
      try GDBConsoleOutputPacket.write(process, session: &self, writer: &writer)
      return .reply
    case .image:
      return .none
    }
  }

  internal mutating func record(_ event: borrowing Debuggee.Event,
                                state: inout GDBRemoteSessionState)
      throws(GDBHandlerError) {
    // Reserve the Stop: prefix used by the initial notification.
    let capacity = max(0, state.negotiation.payload - 5)
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                      { buffer throws(GDBHandlerError) in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      _ = try GDBStopPacket.write(event, session: &self, state: &state,
                                  writer: &writer)
      state.stops.record(writer.output.span)
    })
  }

  internal mutating func snapshot(state: inout GDBRemoteSessionState)
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
}
