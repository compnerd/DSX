// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal borrowing func read(registers payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request =
        try GDBRegisterRequest(payload, debuggee: debuggee, state: state)
    guard request.range.isEmpty else {
      throw .malformed
    }
    let snapshot = try request.thread.snapshot()
    let description = RegisterDescription(snapshot.configuration)
    for index in 0 ..< description.count {
      guard let register = description.register(index),
          case .some = register.numbers.gdb else {
        continue
      }
      try writer.emit(snapshot, register: register, model: description)
    }
  }

  internal borrowing func write(registers payload: borrowing Span<UInt8>,
                                state: borrowing GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request =
        try GDBRegisterRequest(payload, debuggee: debuggee, state: state)
    var snapshot = try request.thread.snapshot()
    var reader = GDBPacketReader(payload.extracting(request.range))
    let description = RegisterDescription(snapshot.configuration)
    for index in 0 ..< description.count {
      guard let register = description.register(index),
          case .some = register.numbers.gdb else {
        continue
      }
      try reader.apply(to: &snapshot, register: register, model: description,
                       scratch: &writer.output)
    }
    guard reader.empty else {
      throw .malformed
    }
    do {
      try snapshot.commit(request.thread)
    } catch {
      throw .debuggee(error)
    }
    try writer.append("OK")
  }

  internal borrowing func read(register payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request =
        try GDBRegisterRequest(payload, debuggee: debuggee, state: state)
    var reader = GDBPacketReader(payload.extracting(request.range))
    let number = try reader.hex()
    let snapshot = try request.thread.snapshot()
    let description = RegisterDescription(snapshot.configuration)
    guard reader.empty, let number = Int(exactly: number),
        let register =
            description.register(number,
                                 compatibility: state.compatibility) else {
      throw .malformed
    }
    do {
      try writer.emit(snapshot, register: register, model: description)
    } catch {
      DSX.log("failed to encode register \(number): \(error)", level: .error,
              channel: .process)
      throw error
    }
  }

  internal borrowing func write(register payload: borrowing Span<UInt8>,
                                state: borrowing GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request =
        try GDBRegisterRequest(payload, debuggee: debuggee, state: state)
    var reader = GDBPacketReader(payload.extracting(request.range))
    let number = try reader.hex()
    var snapshot = try request.thread.snapshot()
    let description = RegisterDescription(snapshot.configuration)
    guard number <= UInt64(Int.max), reader.consume(UInt8(ascii: "=")),
        let register =
            description.register(Int(number),
                                 compatibility: state.compatibility) else {
      throw .malformed
    }
    try reader.apply(to: &snapshot, register: register, model: description,
                     scratch: &writer.output)
    guard reader.empty else {
      throw .malformed
    }
    do {
      try snapshot.commit(request.thread)
    } catch {
      throw .debuggee(error)
    }
    try writer.append("OK")
  }
}
