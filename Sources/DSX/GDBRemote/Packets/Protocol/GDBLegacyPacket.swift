// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBLegacyControlPacket {
  internal static func acknowledge(_ payload: borrowing Span<UInt8>,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append("OK")
  }

  internal static func baud(_ payload: borrowing Span<UInt8>,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    _ = try reader.decimal()
    guard reader.empty else {
      throw .malformed
    }
    try writer.append("OK")
  }
}

internal enum GDBLegacyBreakpointPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address = try Debuggee.Address(rawValue: reader.hex())
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let mode = try reader.read()
    guard reader.empty, mode == UInt8(ascii: "S") ||
        mode == UInt8(ascii: "C") else {
      throw .malformed
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    let site = BreakpointSite(address: address, size: 0, kind: .software)
    do throws(Debuggee.Error) {
      if mode == UInt8(ascii: "S") {
        _ = try session.breakpoints.insert(process, site)
      } else {
        guard let identifier = session.breakpoints.find(process, site) else {
          throw .breakpoint
        }
        try session.breakpoints.remove(process, identifier,
                                       context: &session.control)
      }
    } catch {
      throw .debuggee(error)
    }
    try writer.append("OK")
  }
}

internal enum GDBEchoPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append(payload)
  }
}

internal enum GDBPIDPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: borrowing DebugSession,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    try writer.hex(process.rawValue)
  }
}

internal enum GDBSpeedPacket {
  private static let filler: StaticString =
      "1234567890qwertyuiopasdfghjklzxcvbnm"

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    guard reader.consume("response_size:") else {
      throw .malformed
    }
    let count = try reader.decimal()
    guard reader.consume(UInt8(ascii: ";")), count <= UInt64(Int.max - 5) else {
      throw .malformed
    }
    if count == 0 {
      return try writer.append("OK")
    }
    guard writer.output.freeCapacity >= Int(count) + 5 else {
      throw .capacity
    }
    try writer.append("data:")
    filler.withUTF8Buffer { filler in
      for index in 0 ..< Int(count) {
        writer.output.append(filler[index % filler.count])
      }
    }
  }
}

internal enum GDBDetachSupportPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard DebugCapabilities.current.contains(.detachment) else {
      throw .unsupported
    }
    try writer.append("OK")
  }
}

internal enum GDBInferiorInputPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try GDBPacketReader.decode(payload, into: &writer.output)
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    try translate(session.input(process, bytes: writer.output.span))
    writer.output.removeAll()
    try writer.append("OK")
  }
}

internal enum GDBRemoteCommandPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard matches(payload, command: "exit") else {
      throw .unsupported
    }
    try writer.append("OK")
  }
}

private func matches(_ payload: borrowing Span<UInt8>,
                     command: StaticString) -> Bool {
  guard payload.count == command.utf8CodeUnitCount * 2 else {
    return false
  }
  return command.withUTF8Buffer { command in
    for index in 0 ..< command.count {
      guard let high = GDBPacketReader.digit(payload[index * 2]),
          let low = GDBPacketReader.digit(payload[index * 2 + 1]),
          high << 4 | low == command[index] else {
        return false
      }
    }
    return true
  }
}
