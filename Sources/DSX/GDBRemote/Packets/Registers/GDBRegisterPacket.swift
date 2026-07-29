// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal typealias GDBRegisterSelection =
    (range: Range<Int>, thread: ProcessThreadIdentifier)

internal enum GDBRegisterPacket {
  private typealias Failure = GDBHandlerError

  internal static func request(_ payload: borrowing Span<UInt8>,
                               session: borrowing DebugSession,
                               state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) -> GDBRegisterSelection {
    let suffix =
        try GDBThreadSuffix.parse(payload, enabled: state.negotiation.enabled
                                    .contains(.threadsuffix),
                                  debuggee: session.debuggee)
    let thread =
        try GDBPacketScope.thread(suffix.thread,
                                  selection: state.selection.general,
                                  fallback: state.selection.stopped,
                                  debuggee: session.debuggee)
    return (suffix.range, thread)
  }

  internal static func snapshot(_ thread: ProcessThreadIdentifier)
      throws(GDBHandlerError) -> DebugSession.RegisterState {
    do {
      return try NativeRegisters.snapshot(thread)
    } catch {
      DSX.log("failed to read registers for \(thread): \(error)", level: .error,
              channel: .process)
      throw .debuggee(error)
    }
  }

  internal static func commit(_ snapshot: consuming DebugSession.RegisterState,
                              thread: ProcessThreadIdentifier)
      throws(GDBHandlerError) {
    do {
      try NativeRegisters.commit(consume snapshot, thread: thread)
    } catch {
      throw .debuggee(error)
    }
  }

  internal static func read(_ state: borrowing DebugSession.RegisterState,
                            register: RegisterRecord,
                            model: RegisterDescription,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let count = (register.bits + 7) / 8
    let start = writer.output.count
    try withUnsafePointer(to: state, { state throws(Failure) in
      if let container = container(register, registers: model) {
        let size = (container.bits + 7) / 8
        try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size,
                                          { buffer throws(Failure) in
          var output = OutputSpan(buffer: buffer, initializedCount: 0)
          try translate(NativeRegisters.read(state.pointee,
                                             register: container.identifier,
                                             into: &output))
          guard output.count >= count,
              writer.output.freeCapacity >= count else {
            throw GDBHandlerError.capacity
          }
          for index in 0 ..< count {
            writer.output.append(output[index])
          }
        })
      } else {
        try translate(NativeRegisters.read(state.pointee,
                                           register: register.identifier,
                                           into: &writer.output))
      }
    })
    guard writer.output.count - start == count,
        writer.output.freeCapacity >= count else {
      throw .capacity
    }
    for _ in 0 ..< count {
      writer.output.append(0)
    }
    for index in (0 ..< count).reversed() {
      let byte = writer.output[start + index]
      writer.output[start + index * 2] = GDBPacketWriter.hexadecimal(byte >> 4)
      writer.output[start + index * 2 + 1] = GDBPacketWriter.hexadecimal(byte)
    }
  }

  internal static func write(_ state: inout DebugSession.RegisterState,
                             register: RegisterRecord,
                             model: RegisterDescription,
                             reader: inout GDBPacketReader,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let count = (register.bits + 7) / 8
    guard writer.output.capacity >= count else {
      throw .capacity
    }
    writer.output.removeAll()
    for _ in 0 ..< count {
      let upper = try reader.read()
      let lower = try reader.read()
      guard let high = GDBPacketReader.digit(upper),
          let low = GDBPacketReader.digit(lower) else {
        throw .malformed
      }
      writer.output.append(high << 4 | low)
    }
    try withUnsafeMutablePointer(to: &state, { state throws(Failure) in
      if let container = container(register, registers: model) {
        let size = (container.bits + 7) / 8
        try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size,
                                          { buffer throws(Failure) in
          var output = OutputSpan(buffer: buffer, initializedCount: 0)
          try translate(NativeRegisters.read(state.pointee,
                                             register: container.identifier,
                                             into: &output))
          guard output.count == size else {
            throw GDBHandlerError.debuggee(.register)
          }
          for index in 0 ..< count {
            output[index] = writer.output[index]
          }
          if case .unsigned = register.encoding, register.bits == 32,
              container.bits == 64 {
            for index in count ..< size {
              output[index] = 0
            }
          }
          try translate(NativeRegisters.write(&state.pointee,
                                              register: container.identifier,
                                              bytes: output.span))
        })
      } else {
        try translate(NativeRegisters.write(&state.pointee,
                                            register: register.identifier,
                                            bytes: writer.output.span))
      }
    })
    writer.output.removeAll()
  }
}

private func container(_ register: RegisterRecord,
                       registers: RegisterDescription) -> RegisterRecord? {
  guard register.numbers.gdb == nil,
      let relation = register.relations.containers.first,
      let identifier = registers.relation(relation) else {
    return nil
  }
  return registers.register(identifier)
}
