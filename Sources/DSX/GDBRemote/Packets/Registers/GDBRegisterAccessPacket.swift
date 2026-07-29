// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRegisterPacket {
  internal static func read(_ payload: borrowing Span<UInt8>,
                            session: borrowing DebugSession,
                            state: borrowing GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request =
        try GDBRegisterPacket.request(payload, session: session, state: state)
    guard request.range.isEmpty else {
      throw .malformed
    }
    let snapshot = try GDBRegisterPacket.snapshot(request.thread)
    let description = RegisterDescription()
    for index in 0 ..< description.count {
      guard let register = description.register(index),
          case .some = register.numbers.gdb else {
        continue
      }
      try GDBRegisterPacket.read(snapshot, register: register,
                                 model: description, writer: &writer)
    }
  }
}

extension GDBRegisterPacket {
  internal static func write(_ payload: borrowing Span<UInt8>,
                             session: borrowing DebugSession,
                             state: borrowing GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request =
        try GDBRegisterPacket.request(payload, session: session, state: state)
    var snapshot = try GDBRegisterPacket.snapshot(request.thread)
    var reader = GDBPacketReader(payload.extracting(request.range))
    let description = RegisterDescription()
    for index in 0 ..< description.count {
      guard let register = description.register(index),
          case .some = register.numbers.gdb else {
        continue
      }
      try GDBRegisterPacket.write(&snapshot, register: register,
                                  model: description, reader: &reader,
                                  writer: &writer)
    }
    guard reader.empty else {
      throw .malformed
    }
    try GDBRegisterPacket.commit(snapshot, thread: request.thread)
    try writer.append("OK")
  }
}

extension GDBRegisterPacket {
  internal static func read(_ payload: borrowing Span<UInt8>, number _: Void,
                            session: borrowing DebugSession,
                            state: borrowing GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request =
        try GDBRegisterPacket.request(payload, session: session, state: state)
    var reader = GDBPacketReader(payload.extracting(request.range))
    let number = try reader.hex()
    let description = RegisterDescription()
    guard reader.empty, let number = Int(exactly: number),
        let register =
            description.register(number,
                                 compatibility: state.compatibility) else {
      throw .malformed
    }
    let snapshot = try GDBRegisterPacket.snapshot(request.thread)
    do {
      try GDBRegisterPacket.read(snapshot, register: register,
                                 model: description, writer: &writer)
    } catch {
      DSX.log("failed to encode register \(number): \(error)", level: .error,
              channel: .process)
      throw error
    }
  }
}

extension GDBRegisterPacket {
  internal static func write(_ payload: borrowing Span<UInt8>, number _: Void,
                             session: borrowing DebugSession,
                             state: borrowing GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request =
        try GDBRegisterPacket.request(payload, session: session, state: state)
    var reader = GDBPacketReader(payload.extracting(request.range))
    let number = try reader.hex()
    let description = RegisterDescription()
    guard number <= UInt64(Int.max), reader.consume(UInt8(ascii: "=")),
        let register =
            description.register(Int(number),
                                 compatibility: state.compatibility) else {
      throw .malformed
    }
    var snapshot = try GDBRegisterPacket.snapshot(request.thread)
    try GDBRegisterPacket.write(&snapshot, register: register,
                                model: description, reader: &reader,
                                writer: &writer)
    guard reader.empty else {
      throw .malformed
    }
    try GDBRegisterPacket.commit(snapshot, thread: request.thread)
    try writer.append("OK")
  }
}
