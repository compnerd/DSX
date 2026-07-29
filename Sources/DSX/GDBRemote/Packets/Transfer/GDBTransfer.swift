// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private typealias Failure = Debuggee.Error

internal enum GDBTransferObject: UInt8, Equatable, Sendable {
  case features
  case executable
  case auxiliary
  case libraries
  case svr4
  case threads
  case osdata
  case signal
  case map

  internal var feature: GDBRemoteFeatures {
    switch self {
    case .auxiliary: .auxiliary
    case .executable: .executable
    case .features: .features
    case .libraries: .libraries
    case .svr4: .svr4
    case .osdata: .osdata
    case .signal: .signal
    case .threads: .threads
    case .map: .map
    }
  }
}

extension DebugSession {
  internal borrowing func transfer(_ object: GDBTransferObject,
                                   payload: borrowing Span<UInt8>,
                                   state: inout GDBRemoteSessionState,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let request =
        try GDBTransferRequest(object, payload: payload.extracting(0...),
                               state: state)
    switch object {
    case .features:
      var reader = GDBPacketReader(request.annex)
      guard reader.consume("target.xml"), reader.empty else {
        throw .unsupported
      }
      let registers = try description(state)
      try writer.emit(registers, offset: request.offset, length: request.length,
                      compatibility: state.compatibility)
    case .threads:
      guard request.annex.isEmpty else {
        throw .unsupported
      }
      try writer.emit(threads: debuggee, offset: request.offset,
                      length: request.length)
    case .executable:
      let process: ProcessIdentifier
      if request.annex.isEmpty {
        process = try state.selection.general.process(in: debuggee)
      } else {
        var reader = GDBPacketReader(request.annex)
        process = try ProcessIdentifier(rawValue: reader.hex())
        guard reader.empty, debuggee.contains(process) else {
          throw .debuggee(.process)
        }
      }
      let image = try translate(image(process))
      try writer.transfer(offset: request.offset,
                          length: request.length) { emitter in
        emitter.append(image.path)
      }
    case .libraries, .svr4:
      let capability: DebugCapabilities = object == .svr4 ? .svr4 : .libraries
      guard DebugCapabilities.current.contains(capability) else {
        throw .unsupported
      }
      guard request.annex.isEmpty else {
        throw .unsupported
      }
      let process = try state.selection.general.process(in: debuggee)
      let svr4 = object == .svr4
      try writer.transfer(process, offset: request.offset,
                          length: request.length, svr4: svr4, control: control,
                          executable: launch.executable)
      state.modules = false
    case .map:
      guard request.annex.isEmpty else {
        throw .unsupported
      }
      let process = try state.selection.general.process(in: debuggee)
      try writer.transfer(process, offset: request.offset,
                          length: request.length)
    case .auxiliary:
      guard request.annex.isEmpty,
          DebugCapabilities.current.contains(.auxiliary),
          let process = debuggee.process(state.selection.general) else {
        throw .unsupported
      }
      let offset = request.offset
      let length = request.length
      try writer.transfer(length: length) { limit, output throws(Failure) in
        try process.auxiliary(offset: offset, limit: limit, into: &output)
      }
    case .signal:
      guard request.annex.isEmpty, DebugCapabilities.current.contains(.signal),
          let thread = state.selection.resolve(in: debuggee) else {
        throw .unsupported
      }
      let offset = request.offset
      let length = request.length
      try writer.transfer(length: length) { limit, output throws(Failure) in
        try thread.signal(offset: offset, limit: limit, into: &output)
      }
    case .osdata:
      throw .unsupported
    }
    return .reply
  }
}

internal struct GDBTransferRequest: ~Escapable {
  internal let annex: Span<UInt8>
  internal let offset: UInt64
  internal let length: UInt64

  @_lifetime(copy payload)
  internal init(_ object: GDBTransferObject, payload: consuming Span<UInt8>,
                state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let operation = try reader.field(UInt8(ascii: ":"))
    let annex = try reader.field(UInt8(ascii: ":"))
    guard reader.matches(operation, value: "read") else {
      throw .unsupported
    }
    guard state.negotiation.supported.contains(object.feature) else {
      throw .unsupported
    }
    let offset = try reader.hex()
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let length = try reader.hex()
    _ = reader.consume(UInt8(ascii: ":"))
    guard reader.empty else {
      throw .malformed
    }
    self.annex = payload.extracting(annex)
    self.offset = offset
    self.length = length
  }
}
