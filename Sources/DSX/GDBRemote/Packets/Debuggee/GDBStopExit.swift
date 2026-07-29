// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBStopPacket {
  internal static func exit(_ process: ProcessIdentifier, status: Debuggee.Exit,
                            state: borrowing GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    switch status {
    case .exited(let code):
      try writer.append(UInt8(ascii: "W"))
      try writer.hex(UInt8(truncatingIfNeeded: code))
    case .signalled(let signal):
      try writer.append(UInt8(ascii: "X"))
      try writer.hex(GDBSignal.protocol(signal,
                                        compatibility: state.compatibility))
    }
    guard state.negotiation.enabled.contains(.multiprocess) else {
      return
    }
    try writer.append(";process:")
    try writer.hex(process.rawValue)
  }

  internal static func terminated(_ thread: ProcessThreadIdentifier,
                                  status: CInt,
                                  state: borrowing GDBRemoteSessionState,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append(UInt8(ascii: "w"))
    try writer.hex(UInt8(truncatingIfNeeded: status))
    try writer.append(UInt8(ascii: ";"))
    let multiprocess = state.negotiation.enabled.contains(.multiprocess)
    try writer.thread(thread, multiprocess: multiprocess)
  }
}
