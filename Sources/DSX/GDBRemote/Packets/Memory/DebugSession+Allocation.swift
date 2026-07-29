// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func allocate(_ payload: borrowing Span<UInt8>,
                                  state: borrowing GDBRemoteSessionState,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let size = try reader.hex()
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let bytes = reader.remaining()
    var permissions: MemoryPermissions = []
    for index in 0 ..< bytes.count {
      switch bytes[index] {
      case UInt8(ascii: "r"):
        permissions.insert(.read)
      case UInt8(ascii: "w"):
        permissions.insert(.write)
      case UInt8(ascii: "x"):
        permissions.insert(.execute)
      default:
        throw .malformed
      }
    }
    guard DebugCapabilities.current.contains(.allocation) else {
      throw .unsupported
    }
    let process = try state.selection.general.process(in: debuggee)
    let address =
        try translate(allocate(process, size: size, permissions: permissions))
    try writer.hex(address.rawValue)
  }

  internal mutating func deallocate(_ payload: borrowing Span<UInt8>,
                                    state: borrowing GDBRemoteSessionState,
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
    let process = try state.selection.general.process(in: debuggee)
    try translate(deallocate(process, address: address))
    try writer.append("OK")
  }
}
