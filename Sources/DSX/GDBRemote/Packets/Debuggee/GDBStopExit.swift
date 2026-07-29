// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func exit(_ process: ProcessIdentifier,
                              status: Debuggee.Exit,
                              state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    switch status {
    case .exited(let code):
      try append(UInt8(ascii: "W"))
      try hex(UInt8(truncatingIfNeeded: code))
    case .signalled(let signal):
      try append(UInt8(ascii: "X"))
      try hex(state.compatibility.signal(signal))
    }
    if state.negotiation.enabled.contains(.multiprocess) {
      try append(";process:")
      try hex(process.rawValue)
    }
    if case .signalled(let signal) = status, state.compatibility == .lldb {
      try append(";description:")
      try encoded("Terminated due to signal ")
      try encoded(UInt64(signal))
      try append(UInt8(ascii: ";"))
    }
  }

  internal mutating func terminated(_ identifier: ProcessThreadIdentifier,
                                    status: CInt,
                                    state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    try append(UInt8(ascii: "w"))
    try hex(UInt8(truncatingIfNeeded: status))
    try append(UInt8(ascii: ";"))
    let multiprocess = state.negotiation.enabled.contains(.multiprocess)
    try thread(identifier, multiprocess: multiprocess)
  }
}
