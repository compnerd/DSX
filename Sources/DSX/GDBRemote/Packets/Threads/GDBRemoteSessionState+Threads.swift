// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemoteSessionState {
  internal mutating func restart(threads debuggee: borrowing Debuggee,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    enumeration.thread = 0
    return try threads(debuggee, writer: &writer)
  }

  internal mutating func threads(_ debuggee: borrowing Debuggee,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if debuggee.processes.isEmpty, compatibility == .lldb {
      try writer.append("OK")
      enumeration.thread = nil
      return
    }
    guard let cursor = enumeration.thread else {
      return try writer.append(UInt8(ascii: "l"))
    }
    var offset = cursor
    let multiprocess = negotiation.enabled.contains(.multiprocess)
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
        let size = thread.identifier.size(multiprocess: multiprocess) + 1
        guard writer.capacity - writer.count >= size else {
          if first {
            throw .capacity
          }
          return
        }
        try writer.append(first ? UInt8(ascii: "m") : UInt8(ascii: ","))
        try writer.thread(thread.identifier, multiprocess: multiprocess)
        enumeration.thread = cursor + emitted + 1
        emitted += 1
        first = false
      }
    }
    if first {
      try writer.append(UInt8(ascii: "l"))
    }
    enumeration.thread = nil
  }
}
