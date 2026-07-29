// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBNegotiationPacket {
  internal static func suffix(_ payload: borrowing Span<UInt8>,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    state.negotiation.enable(.threadsuffix)
    try writer.append("OK")
    return .reply
  }
}

extension GDBNegotiationPacket {
  internal static func errors(_ payload: borrowing Span<UInt8>,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.count == 0 else {
      throw .malformed
    }
    state.messages = true
    try writer.append("OK")
  }
}

extension GDBNegotiationPacket {
  internal static func threads(_ payload: borrowing Span<UInt8>,
                               state: inout GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    state.negotiation.enable(.stopthreads)
    try writer.append("OK")
    return .reply
  }
}

internal enum GDBSignalControlPacket {
  internal static func pass(_ payload: borrowing Span<UInt8>,
                            signals: inout SignalSet,
                            state: borrowing GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard NativeDebugControl.capabilities.contains(.passthrough) else {
      throw .unsupported
    }
    try DSX::signals(payload, compatibility: state.compatibility,
                     into: &signals)
    try writer.append("OK")
  }
}

extension GDBSignalControlPacket {
  internal static func program(_ payload: borrowing Span<UInt8>,
                               state: inout GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try signals(payload, into: &state.delivery)
    try writer.append("OK")
  }
}

internal enum GDBStreamPacket {
  internal static func input(_ payload: borrowing Span<UInt8>,
                             launch: inout Debuggee.Launch,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    launch.input = try GDBPacketReader.string(payload)
    try writer.append("OK")
  }
}

extension GDBStreamPacket {
  internal static func output(_ payload: borrowing Span<UInt8>,
                              launch: inout Debuggee.Launch,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    launch.output = try GDBPacketReader.string(payload)
    try writer.append("OK")
  }
}

extension GDBStreamPacket {
  internal static func error(_ payload: borrowing Span<UInt8>,
                             launch: inout Debuggee.Launch,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    launch.error = try GDBPacketReader.string(payload)
    try writer.append("OK")
  }
}

extension GDBNegotiationPacket {
  internal static func packet(_ payload: borrowing Span<UInt8>,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let capacity = try reader.hex()
    guard reader.empty, capacity > 0, capacity <= UInt64(Int.max) else {
      throw .malformed
    }
    state.negotiation.limit(Int(capacity))
    try writer.append("OK")
  }
}

extension GDBNegotiationPacket {
  internal static func payload(_ payload: borrowing Span<UInt8>,
                               state: inout GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let capacity = try reader.hex()
    guard reader.empty, capacity > 0, capacity <= UInt64(Int.max) else {
      throw .malformed
    }
    state.negotiation.limit(Int(capacity))
    try writer.append("OK")
  }
}

internal enum GDBRegisterStatePacket {
  internal static func sync(_ payload: borrowing Span<UInt8>,
                            session: inout DebugSession,
                            state: inout GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    guard reader.consume(UInt8(ascii: ":")) else {
      throw .malformed
    }
    let selection =
        try GDBThreadIdentifier.parse(reader.remaining(),
                                      debuggee: session.debuggee)
    guard case .thread(let thread) = selection else {
      throw .debuggee(.thread)
    }
    try translate(NativeRegisters.synchronize(thread))
    try writer.append("OK")
  }
}

extension GDBRegisterStatePacket {
  internal static func save(_ payload: borrowing Span<UInt8>,
                            session: inout DebugSession,
                            state: inout GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let thread = try saved(payload, state: state, debuggee: session.debuggee)
    let identifier = try translate(session.save(thread))
    try writer.decimal(identifier)
  }
}

extension GDBRegisterStatePacket {
  internal static func restore(_ payload: borrowing Span<UInt8>,
                               session: inout DebugSession,
                               state: inout GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let identifier = try reader.decimal()
    let thread = try thread(reader.remaining(), empty: reader.empty,
                            state: state, debuggee: session.debuggee)
    do {
      try session.restore(identifier, thread: thread)
    } catch {
      DSX.log("failed to restore register state: \(error)", level: .error,
              channel: .process)
      throw .debuggee(error)
    }
    try writer.append("OK")
  }
}

private func thread(_ payload: borrowing Span<UInt8>, empty: Bool,
                    state: borrowing GDBRemoteSessionState,
                    debuggee: borrowing Debuggee)
    throws(GDBHandlerError) -> ProcessThreadIdentifier? {
  if empty {
    return nil
  }
  return try saved(payload, state: state, debuggee: debuggee)
}

private func saved(_ payload: borrowing Span<UInt8>,
                   state: borrowing GDBRemoteSessionState,
                   debuggee: borrowing Debuggee)
    throws(GDBHandlerError) -> ProcessThreadIdentifier {
  if payload.count == 0 {
    let selected = debuggee.resolve(state.selection.general)
    if let selected {
      return selected
    }
    if let stopped = state.selection.stopped {
      return stopped
    }
    throw .debuggee(.thread)
  }
  var start = 0
  if payload[start] == UInt8(ascii: ";") {
    start += 1
  }
  var end = payload.count
  if payload[end - 1] == UInt8(ascii: ";") {
    end -= 1
  }
  var reader = GDBPacketReader(payload.extracting(start ..< end))
  guard reader.consume("thread:") else {
    throw .malformed
  }
  let selection =
      try GDBThreadIdentifier.parse(reader.remaining(), debuggee: debuggee)
  guard case .thread(let thread) = selection else {
    throw .debuggee(.thread)
  }
  return thread
}

private func signals(_ payload: borrowing Span<UInt8>,
                     compatibility: CompatibilityMode? = nil,
                     into output: inout SignalSet) throws(GDBHandlerError) {
  var signals = SignalSet()
  var reader = GDBPacketReader(payload.extracting(0...))
  while reader.empty == false {
    let signal = try reader.hex()
    guard signal <= UInt8.max else {
      throw .malformed
    }
    let native: CInt? = if let compatibility {
      GDBSignal.native(signal, compatibility: compatibility)
    } else {
      CInt(signal)
    }
    guard let native, let number = UInt8(exactly: native) else {
      throw .malformed
    }
    signals.insert(number)
    if reader.empty || reader.consume(UInt8(ascii: ";")) {
      continue
    }
    while reader.consume(UInt8(ascii: " ")) {
    }
    guard reader.empty else {
      throw .malformed
    }
  }
  output = signals
}
