// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func baud(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    _ = try reader.decimal()
    guard reader.empty else {
      throw .malformed
    }
    try append("OK")
  }
}

extension DebugSession {
  internal mutating func breakpoint(_ payload: borrowing Span<UInt8>,
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
    let process = try state.selection.general.process(in: debuggee)
    let site = ABI.breakpoint(address)
    do throws(Debuggee.Error) {
      switch mode {
      case UInt8(ascii: "S"):
        _ = try breakpoints.insert(process, site)
      case UInt8(ascii: "C"):
        if let identifier = breakpoints.find(process, site) {
          try breakpoints.remove(process, identifier, context: &control)
        }
      default:
        throw .state
      }
    } catch {
      throw .debuggee(error)
    }
    try writer.append("OK")
  }
}

extension DebugSession {
  internal borrowing func pid(_ payload: borrowing Span<UInt8>,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try state.selection.general.process(in: debuggee)
    try writer.hex(process.rawValue)
  }
}

extension GDBPacketWriter {
  private static let filler: StaticString =
      "1234567890qwertyuiopasdfghjklzxcvbnm"

  internal mutating func speed(_ payload: borrowing Span<UInt8>)
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
      return try append("OK")
    }
    guard output.freeCapacity >= Int(count) + 5 else {
      throw .capacity
    }
    try append("data:")
    GDBPacketWriter.filler.withUTF8Buffer { filler in
      for index in 0 ..< Int(count) {
        output.append(filler[index % filler.count])
      }
    }
  }
}

extension GDBPacketWriter {
  internal mutating func detachment(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    guard DebugCapabilities.current.contains(.detachment) else {
      throw .unsupported
    }
    try append("OK")
  }
}

extension DebugSession {
  internal mutating func input(_ payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.output.decode(payload)
    let process = try state.selection.general.process(in: debuggee)
    try translate(input(process, bytes: writer.output.span))
    writer.output.removeAll()
    try writer.append("OK")
  }
}

extension GDBPacketWriter {
  internal mutating func command(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    guard payload.matches(command: "exit") else {
      throw .unsupported
    }
    try append("OK")
  }
}

extension Span where Element == UInt8 {
  fileprivate func matches(command: StaticString) -> Bool {
    guard count == command.utf8CodeUnitCount * 2 else {
      return false
    }
    return command.withUTF8Buffer { command in
      for index in 0 ..< command.count {
        guard let high = UInt8(hex: self[index * 2]),
            let low = UInt8(hex: self[index * 2 + 1]),
            high << 4 | low == command[index] else {
          return false
        }
      }
      return true
    }
  }
}
