// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBAllocationPacket {
  internal static func allocate(_ payload: borrowing Span<UInt8>,
                                session: inout DebugSession,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let size = try reader.hex()
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let permissions = reader.remaining()
    var readable = false
    var writable = false
    var executable = false
    for index in 0 ..< permissions.count {
      switch permissions[index] {
      case UInt8(ascii: "r"):
        readable = true
      case UInt8(ascii: "w"):
        writable = true
      case UInt8(ascii: "x"):
        executable = true
      default:
        throw .malformed
      }
    }
    guard DebugCapabilities.current.contains(.allocation) else {
      throw .unsupported
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    let address =
        try translate(session.allocate(process, size: size, readable: readable,
                                       writable: writable,
                                       executable: executable))
    try writer.hex(address.rawValue)
  }
}

extension GDBAllocationPacket {
  internal static func deallocate(_ payload: borrowing Span<UInt8>,
                                  session: inout DebugSession,
                                  state: inout GDBRemoteSessionState,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try Debuggee.Address(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    guard DebugCapabilities.current.contains(.allocation) else {
      throw .unsupported
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    try translate(session.deallocate(process, address: address))
    try writer.append("OK")
  }
}
