// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBExecution {
  internal static func resume(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBExecution.resume(payload, operation: .resume, signal: nil,
                            session: &session, state: &state)
    return try GDBExecution.reply(state: &state, writer: &writer)
  }
}

extension GDBExecution {
  internal static func step(_ payload: borrowing Span<UInt8>,
                            session: inout DebugSession,
                            state: inout GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBExecution.resume(payload, operation: .step, signal: nil,
                            session: &session, state: &state)
    return try GDBExecution.reply(state: &state, writer: &writer)
  }
}

internal enum GDBSignalResumePacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let (signal, address) =
        try GDBExecution.signal(payload, compatibility: state.compatibility)
    try GDBExecution.resume(address: address, operation: .resume,
                            signal: signal, session: &session, state: &state)
    return try GDBExecution.reply(state: &state, writer: &writer)
  }
}

internal enum GDBSignalStepPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let (signal, address) =
        try GDBExecution.signal(payload, compatibility: state.compatibility)
    try GDBExecution.resume(address: address, operation: .step, signal: signal,
                            session: &session, state: &state)
    return try GDBExecution.reply(state: &state, writer: &writer)
  }
}

extension GDBExecution {
  internal static func interrupt(_ payload: borrowing Span<UInt8>,
                                 session: inout DebugSession,
                                 state: inout GDBRemoteSessionState,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let selection = state.selection.resume
    let process =
        try GDBPacketScope.process(selection, debuggee: session.debuggee)
    guard try translate(session.interrupt(process)) else {
      return try GDBStopPacket.handle(payload, session: &session, state: &state,
                                      writer: &writer)
    }
    return .none
  }
}

extension GDBExecution {
  internal static func detach(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let stopped = reader.consume(UInt8(ascii: "1"))
    let process =
        try GDBExecution.process(reader.remaining(),
                                 selection: state.selection.resume,
                                 debuggee: session.debuggee)
    try translate(session.detach(process, stopped: stopped))
    try writer.append("OK")
  }
}

extension GDBExecution {
  internal static func kill(_ payload: borrowing Span<UInt8>,
                            session: inout DebugSession,
                            state: inout GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let selection = state.selection.resume
    let process =
        try GDBPacketScope.process(selection, debuggee: session.debuggee)
    try translate(session.terminate(process))
    if state.nonstop {
      try writer.append("OK")
      return .reply
    }
    state.termination = .legacy(process)
    return .none
  }
}

extension GDBExecution {
  internal static func attach(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    var reader = GDBPacketReader(payload.extracting(0...))
    let process = try ProcessIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    try translate(session.attach(process))
    guard let event = try translate(session.settle()) else {
      throw .unexpected
    }
    state.observe(event)
    if let failure = session.failure() {
      throw .debuggee(failure)
    }
    return try GDBStopPacket.write(event, session: &session, state: &state,
                                   writer: &writer)
  }
}

extension GDBExecution {
  internal static func vcont(_ payload: borrowing Span<UInt8>,
                             session: inout DebugSession,
                             state: inout GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    if payload.count == 1, payload[0] == UInt8(ascii: "?") {
      try writer.append("vCont;c;C;s;S;t")
      return .reply
    }
    guard payload.count > 1, payload[0] == UInt8(ascii: ";") else {
      throw .malformed
    }
    let empty = Debuggee.Continuation(selection: .all, operation: .resume)
    var actions =
        Configuration.ResumeActionStorage<Debuggee.Continuation> { _ in empty }
    var overflow = Array<Debuggee.Continuation>()
    var count = 0
    var start = 1
    while start < payload.count {
      var end = start
      while end < payload.count {
        guard payload[end] == UInt8(ascii: ";") else {
          end += 1
          continue
        }
        break
      }
      let contents = payload.extracting(start ..< end)
      let parsed = try action(contents, compatibility: state.compatibility,
                              debuggee: session.debuggee)
      if count < actions.count, overflow.isEmpty {
        actions[count] = parsed
      } else {
        if overflow.isEmpty {
          overflow.reserveCapacity(actions.count * 2)
          for index in 0 ..< count {
            overflow.append(actions[index])
          }
        }
        overflow.append(parsed)
      }
      count += 1
      start = end + 1
    }
    guard count > 0 else {
      throw .malformed
    }
    if overflow.isEmpty {
      let span = actions.span.extracting(0 ..< count)
      return try execute(span, session: &session, state: &state,
                         writer: &writer)
    }
    return try execute(overflow.span, session: &session, state: &state,
                       writer: &writer)
  }
}

internal enum GDBExecution {
  internal typealias Actions = Debuggee.Continuations

  internal static func resume(_ payload: borrowing Span<UInt8>,
                              operation: Debuggee.Continuation.Operation,
                              signal: CInt?, session: inout DebugSession,
                              state: inout GDBRemoteSessionState)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let address: Debuggee.Address? = if reader.empty {
      nil
    } else {
      try Debuggee.Address(rawValue: reader.hex())
    }
    guard reader.empty else {
      throw .malformed
    }
    try resume(address: address, operation: operation, signal: signal,
               session: &session, state: &state)
  }

  internal static func resume(address: Debuggee.Address?,
                              operation: Debuggee.Continuation.Operation,
                              signal: CInt?, session: inout DebugSession,
                              state: inout GDBRemoteSessionState)
      throws(GDBHandlerError) {
    let selection = state.selection.resume
    let action = Debuggee.Continuation(selection: selection,
                                       operation: operation, signal: signal,
                                       address: address)
    if operation == .resume, case .thread(let thread) = selection {
      let fallback =
          Debuggee.Continuation(selection: .process(thread.process),
                                operation: .resume)
      let actions: InlineArray<2, Debuggee.Continuation> = [action, fallback]
      try start(actions.span, session: &session, state: state)
    } else {
      let actions: InlineArray<1, Debuggee.Continuation> = [action]
      try start(actions.span, session: &session, state: state)
    }
  }

  internal static func start(_ actions: borrowing Actions,
                             session: inout DebugSession,
                             state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    let selection = state.selection.resume
    let process =
        try GDBPacketScope.process(selection, debuggee: session.debuggee)
    try translate(session.resume(actions, process: process))
  }

  internal static func reply(state: inout GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard state.nonstop else {
      return .none
    }
    try writer.append("OK")
    return .reply
  }

  internal static func signal(_ payload: borrowing Span<UInt8>,
                              compatibility: CompatibilityMode)
      throws(GDBHandlerError) -> (CInt, Debuggee.Address?) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let signal = try reader.hex()
    guard let signal =
        GDBSignal.native(signal, compatibility: compatibility) else {
      throw .malformed
    }
    if reader.consume(UInt8(ascii: ";")) {
      let address = try Debuggee.Address(rawValue: reader.hex())
      guard reader.empty else {
        throw .malformed
      }
      return (signal, address)
    }
    guard reader.empty else {
      throw .malformed
    }
    return (signal, nil)
  }

  internal static func process(_ payload: borrowing Span<UInt8>,
                               selection: Debuggee.Thread.Selection,
                               debuggee: borrowing Debuggee)
      throws(GDBHandlerError) -> ProcessIdentifier {
    guard !payload.isEmpty else {
      return try GDBPacketScope.process(selection, debuggee: debuggee)
    }
    var reader = GDBPacketReader(payload.extracting(0...))
    guard reader.consume(UInt8(ascii: ";")) else {
      throw .malformed
    }
    let process = try ProcessIdentifier(rawValue: reader.hex())
    guard reader.empty, debuggee.contains(process) else {
      throw .debuggee(.process)
    }
    return process
  }
}

private func execute(_ actions: borrowing Debuggee.Continuations,
                     session: inout DebugSession,
                     state: inout GDBRemoteSessionState,
                     writer: inout GDBPacketWriter)
    throws(GDBHandlerError) -> GDBPacketDisposition {
  if state.nonstop {
    for index in 0 ..< actions.count
        where actions[index].operation == .stop {
      let action = actions[index]
      guard actions.count == 1, action.selection == .all else {
        throw .code(GDBErrorCode.invalid)
      }
      let process = try GDBPacketScope.process(state.selection.resume,
                                               debuggee: session.debuggee)
      _ = try translate(session.interrupt(process))
      return try GDBExecution.reply(state: &state, writer: &writer)
    }
  }
  try GDBExecution.start(actions, session: &session, state: state)
  return try GDBExecution.reply(state: &state, writer: &writer)
}

private func action(_ payload: borrowing Span<UInt8>,
                    compatibility: CompatibilityMode,
                    debuggee: borrowing Debuggee)
    throws(GDBHandlerError) -> Debuggee.Continuation {
  guard payload.count > 0 else {
    throw .malformed
  }
  var split = 0
  while split < payload.count {
    guard payload[split] == UInt8(ascii: ":") else {
      split += 1
      continue
    }
    break
  }
  var reader = GDBPacketReader(payload.extracting(0 ..< split))
  let command = try reader.read()
  let (operation, signal) =
      try operation(command, compatibility: compatibility, reader: &reader)
  guard reader.empty else {
    throw .malformed
  }
  let selection = try selection(payload, split: split, debuggee: debuggee)
  return Debuggee.Continuation(selection: selection, operation: operation,
                               signal: signal)
}

private func selection(_ payload: borrowing Span<UInt8>, split: Int,
                       debuggee: borrowing Debuggee)
    throws(GDBHandlerError) -> Debuggee.Thread.Selection {
  guard split < payload.count else {
    return .all
  }
  return try GDBThreadIdentifier.parse(payload.extracting((split + 1)...),
                                       debuggee: debuggee)
}

private func operation(_ command: UInt8, compatibility: CompatibilityMode,
                       reader: inout GDBPacketReader)
    throws(GDBHandlerError) -> (Debuggee.Continuation.Operation, CInt?) {
  switch command {
  case UInt8(ascii: "c"):
    return (.resume, nil)
  case UInt8(ascii: "s"):
    return (.step, nil)
  case UInt8(ascii: "t"):
    return (.stop, nil)
  case UInt8(ascii: "C"), UInt8(ascii: "S"):
    let value = try reader.hex()
    guard let signal =
        GDBSignal.native(value, compatibility: compatibility) else {
      throw .malformed
    }
    let operation: Debuggee.Continuation.Operation =
        command == UInt8(ascii: "C") ? .resume : .step
    return (operation, signal)
  default:
    throw .unsupported
  }
}
