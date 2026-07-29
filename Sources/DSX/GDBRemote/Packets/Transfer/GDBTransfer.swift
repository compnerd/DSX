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

internal enum GDBTransferPacket {
  internal static func handle(_ object: GDBTransferObject,
                              payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let request =
        try GDBTransferPacket.parse(object, payload: payload, state: state)
    switch request.object {
    case .features:
      let reader = GDBPacketReader(payload.extracting(0...))
      guard reader.matches(request.annex, value: "target.xml") else {
        throw .unsupported
      }
      let registers = RegisterDescription()
      try GDBRegisterFeaturesPacket.write(offset: request.offset,
                                          length: request.length,
                                          registers: registers,
                                          compatibility: state.compatibility,
                                          writer: &writer)
    case .threads:
      guard request.annex.isEmpty else {
        throw .unsupported
      }
      try GDBThreadTransferPacket.write(offset: request.offset,
                                        length: request.length,
                                        debuggee: session.debuggee,
                                        writer: &writer)
    case .executable:
      let process = try process(request, packet: payload,
                                debuggee: session.debuggee, state: state)
      let image = try translate(session.image(process))
      try writer.transfer(offset: request.offset,
                          length: request.length) { emitter, output in
        emitter.append(image.path, into: &output)
      }
    case .libraries, .svr4:
      let capability: DebugCapabilities =
          request.object == .svr4 ? .svr4 : .libraries
      guard DebugCapabilities.current.contains(capability) else {
        throw .unsupported
      }
      guard request.annex.isEmpty else {
        throw .unsupported
      }
      let process = try GDBPacketScope.process(state.selection.general,
                                               debuggee: session.debuggee)
      let svr4 = request.object == .svr4
      try writer.transfer(process, offset: request.offset,
                          length: request.length, svr4: svr4,
                          executable: session.launch.executable)
      state.modules = false
    case .map:
      guard request.annex.isEmpty else {
        throw .unsupported
      }
      let process = try GDBPacketScope.process(state.selection.general,
                                               debuggee: session.debuggee)
      try writer.transfer(process, offset: request.offset,
                          length: request.length)
    case .auxiliary, .osdata, .signal:
      try read(request, packet: payload, debuggee: session.debuggee,
               state: state, writer: &writer)
    }
    return .reply
  }

  internal static func parse(_ object: GDBTransferObject,
                             payload: borrowing Span<UInt8>,
                             state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) -> GDBTransferRequest {
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
    return GDBTransferRequest(object: object, annex: annex, offset: offset,
                              length: length)
  }
}

internal struct GDBTransferRequest: Sendable {
  internal let object: GDBTransferObject
  internal let annex: Range<Int>
  internal let offset: UInt64
  internal let length: UInt64
}

private func read(_ request: GDBTransferRequest, packet: borrowing Span<UInt8>,
                  debuggee: borrowing Debuggee,
                  state: borrowing GDBRemoteSessionState,
                  writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  let reader = GDBPacketReader(packet.extracting(0...))
  guard reader.span(request.annex).isEmpty else {
    throw .unsupported
  }
  let fallback = state.selection.stopped
  let (process, thread) = GDBPacketScope.scope(state.selection.general,
                                               fallback: fallback,
                                               debuggee: debuggee)
  switch request.object {
  case .auxiliary:
    guard DebugCapabilities.current.contains(.auxiliary), let process else {
      throw .unsupported
    }
    let length = request.length
    try writer.transfer(length: length) { limit, output throws(Failure) in
      try process.auxiliary(offset: request.offset, limit: limit, into: &output)
    }
  case .signal:
    guard DebugCapabilities.current.contains(.signal), let thread else {
      throw .unsupported
    }
    let length = request.length
    try writer.transfer(length: length) { limit, output throws(Failure) in
      try thread.signal(offset: request.offset, limit: limit, into: &output)
    }
    case .executable, .features, .libraries, .svr4, .map, .osdata, .threads:
    throw .unsupported
  }
}

private func process(_ request: GDBTransferRequest,
                     packet: borrowing Span<UInt8>,
                     debuggee: borrowing Debuggee,
                     state: borrowing GDBRemoteSessionState)
    throws(GDBHandlerError) -> ProcessIdentifier {
  let annex = GDBPacketReader(packet.extracting(request.annex))
  if annex.empty {
    return try GDBPacketScope.process(state.selection.general,
                                      debuggee: debuggee)
  }
  var reader = annex
  let process = try ProcessIdentifier(rawValue: reader.hex())
  guard reader.empty, debuggee.contains(process) else {
    throw .debuggee(.process)
  }
  return process
}
