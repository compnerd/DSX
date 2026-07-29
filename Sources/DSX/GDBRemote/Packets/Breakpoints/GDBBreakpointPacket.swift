// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func insert(_ payload: borrowing Span<UInt8>,
                                state: borrowing GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let site = try BreakpointSite(payload)
    try insert(site, selection: state.selection.general)
    try writer.append("OK")
  }
}

extension DebugSession {
  internal mutating func remove(_ payload: borrowing Span<UInt8>,
                                state: borrowing GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let site = try BreakpointSite(payload)
    try remove(site, selection: state.selection.general)
    try writer.append("OK")
  }
}

extension DebugSession {
  internal mutating func insert(_ site: borrowing BreakpointSite,
                                selection: Debuggee.Thread.Selection)
      throws(GDBHandlerError) {
    let process = try selection.process(in: debuggee)
    do {
      let capacity: Int? = switch site.kind {
      case .watchpoint: try watchpoints(process)
      case .hardware, .software: nil
      }
      _ = try breakpoints.insert(process, site, capacity: capacity,
                                 context: &control)
    } catch {
      error.log("failed to insert breakpoint")
      throw .debuggee(error)
    }
  }

  internal mutating func remove(_ site: borrowing BreakpointSite,
                                selection: Debuggee.Thread.Selection)
      throws(GDBHandlerError) {
    let process = try selection.process(in: debuggee)
    guard let identifier = breakpoints.find(process, site) else {
      throw .debuggee(.breakpoint)
    }
    try translate(breakpoints.remove(process, identifier, context: &control))
  }
}

extension BreakpointSite {
  internal init(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
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
    self.init(address: address, size: Int(size), kind: kind)
  }
}
