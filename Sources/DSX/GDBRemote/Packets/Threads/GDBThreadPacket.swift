// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBThreadEnumerationPacket {
  internal static func first(debuggee: borrowing Debuggee,
                             state: inout GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    state.enumeration.thread = 0
    return try next(debuggee: debuggee, state: &state, writer: &writer)
  }

  internal static func next(debuggee: borrowing Debuggee,
                            state: inout GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if debuggee.processes.isEmpty, state.compatibility == .lldb {
      try writer.append("OK")
      state.enumeration.thread = nil
      return
    }
    guard let cursor = state.enumeration.thread else {
      return try writer.append(UInt8(ascii: "l"))
    }
    var offset = cursor
    let multiprocess = state.negotiation.enabled.contains(.multiprocess)
    var emitted = 0
    var first = true
    for process in debuggee.processes {
      for thread in process.threads {
        guard debuggee.alive(thread.identifier) else {
          continue
        }
        if offset > 0 {
          offset -= 1
          continue
        }
        let size = GDBThreadIdentifier.size(thread.identifier,
                                            multiprocess: multiprocess) + 1
        guard writer.capacity - writer.count >= size else {
          if first {
            throw .capacity
          }
          return
        }
        try writer.append(first ? UInt8(ascii: "m") : UInt8(ascii: ","))
        try writer.thread(thread.identifier, multiprocess: multiprocess)
        state.enumeration.thread = cursor + emitted + 1
        emitted += 1
        first = false
      }
    }
    if first {
      try writer.append(UInt8(ascii: "l"))
    }
    state.enumeration.thread = nil
  }
}
