// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBBreakpointPacket {
  internal static func insert(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let site = try GDBBreakpointPacket.parse(payload)
    try GDBBreakpointPacket.insert(site, session: &session, state: state)
    try writer.append("OK")
  }
}

extension GDBBreakpointPacket {
  internal static func remove(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let site = try GDBBreakpointPacket.parse(payload)
    try GDBBreakpointPacket.remove(site, session: &session, state: state)
    try writer.append("OK")
  }
}

internal enum GDBBreakpointPacket {
  internal static func insert(_ site: borrowing BreakpointSite,
                              session: inout DebugSession,
                              state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    do {
      let capacity: Int? = switch site.kind {
      case .watchpoint: try session.watchpoints(process)
      case .hardware, .software: nil
      }
      _ = try session.breakpoints.insert(process, site, capacity: capacity,
                                         context: &session.control)
    } catch {
      DSX.log("failed to insert breakpoint: \(error)", level: .error,
              channel: .process)
      throw .debuggee(error)
    }
  }

  internal static func remove(_ site: borrowing BreakpointSite,
                              session: inout DebugSession,
                              state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    guard let identifier = session.breakpoints.find(process, site) else {
      return
    }
    try translate(session.breakpoints.remove(process, identifier,
                                             context: &session.control))
  }

  internal static func parse(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) -> BreakpointSite {
    var reader = GDBPacketReader(payload.extracting(0...))
    let type = try reader.hex()
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let address = try Debuggee.Address(rawValue: reader.hex())
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let size = try reader.hex()
    guard size > 0, size <= UInt64(Int.max) else {
      throw .malformed
    }
    guard reader.empty else {
      throw .unsupported
    }
    let kind: BreakpointKind = switch type {
    case 0: .software
    case 1: .hardware
    case 2: .watchpoint(.write)
    case 3: .watchpoint(.read)
    case 4: .watchpoint(.readwrite)
    default: throw .unsupported
    }
    return BreakpointSite(address: address, size: Int(size), kind: kind)
  }
}
