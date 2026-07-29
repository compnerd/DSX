// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

// MARK: - Execution

extension DebugSession {
  internal mutating func resume(_ payload: borrowing Span<UInt8>,
                                operation: Debuggee.Continuation.Operation,
                                signal: Bool = false,
                                state: borrowing GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    var reader = GDBPacketReader(payload.extracting(0...))
    let parsed: (signal: CInt?, address: Debuggee.Address?) = if signal {
      try reader.signal(compatibility: state.compatibility)
    } else {
      try (nil, reader.address())
    }
    try resume(address: parsed.address, operation: operation,
               signal: parsed.signal, state: state)
    return try writer.resumed(nonstop: state.nonstop)
  }
}

extension DebugSession {
  internal mutating func interrupt(_ payload: borrowing Span<UInt8>,
                                   state: inout GDBRemoteSessionState,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let selection = state.selection.resume
    let process = try selection.process(in: debuggee)
    guard try translate(interrupt(process)) else {
      return try status(payload, state: &state, writer: &writer)
    }
    return .none
  }
}

extension DebugSession {
  internal mutating func detach(_ payload: borrowing Span<UInt8>,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let stopped = reader.consume(UInt8(ascii: "1"))
    if reader.empty {
      while let process = debuggee.processes.last?.identifier {
        try translate(detach(process, stopped: stopped))
      }
    } else {
      let process =
          try reader.process(selection: state.selection.resume,
                             debuggee: debuggee)
      try translate(detach(process, stopped: stopped))
    }
    try writer.append("OK")
  }
}

extension DebugSession {
  internal mutating func kill(_ payload: borrowing Span<UInt8>,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let selection = state.selection.resume
    let process = try selection.process(in: debuggee)
    try translate(terminate())
    if state.nonstop {
      try writer.append("OK")
      return .reply
    }
    state.termination = .legacy(process)
    return .none
  }
}

extension DebugSession {
  internal mutating func attach(_ payload: borrowing Span<UInt8>,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    var reader = GDBPacketReader(payload.extracting(0...))
    let process = try ProcessIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    try translate(attach(process))
    guard let event = try translate(settle()) else {
      throw .unexpected
    }
    state.observe(event)
    if let failure = failure() {
      throw .debuggee(failure)
    }
    return try emit(event, state: &state, writer: &writer)
  }
}

extension DebugSession {
  internal mutating func vcont(_ payload: borrowing Span<UInt8>,
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
      let compatibility = state.compatibility
      let parsed =
          try Debuggee.Continuation(contents, compatibility: compatibility,
                                    debuggee: debuggee)
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
      return try execute(span, state: &state, writer: &writer)
    }
    return try execute(overflow.span, state: &state, writer: &writer)
  }
}

extension DebugSession {
  internal mutating func resume(address: Debuggee.Address?,
                                operation: Debuggee.Continuation.Operation,
                                signal: CInt?,
                                state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    var selection = state.selection.resume
    if state.nonstop {
      let process = try selection.process(in: debuggee)
      if case .running = debuggee.state(process) {
        throw .code(GDBErrorCode.busy)
      }
    }
    let delivery: Debuggee.Continuation.Delivery = switch selection {
    case .thread: .thread
    case .all, .any, .process: .process
    }
    if delivery == .process, signal != nil {
      selection = try .process(selection.process(in: debuggee))
    }
    let action = Debuggee.Continuation(selection: selection,
                                       operation: operation, signal: signal,
                                       address: address, delivery: delivery)
    if operation == .resume, case .thread(let thread) = selection {
      let fallback =
          Debuggee.Continuation(selection: .process(thread.process),
                                operation: .resume)
      let actions: InlineArray<2, Debuggee.Continuation> = [action, fallback]
      try start(actions.span, state: state)
    } else {
      let actions: InlineArray<1, Debuggee.Continuation> = [action]
      try start(actions.span, state: state)
    }
  }

  internal mutating func start(_ actions: borrowing Debuggee.Continuations,
                               state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    let selection = state.selection.resume
    let process = try selection.process(in: debuggee)
    try translate(resume(actions, process: process))
  }
}

extension DebugSession {
  private mutating func execute(_ actions: borrowing Debuggee.Continuations,
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
        let process = try state.selection.resume.process(in: debuggee)
        _ = try translate(interrupt(process))
        return try writer.resumed(nonstop: state.nonstop)
      }
    }
    try start(actions, state: state)
    return try writer.resumed(nonstop: state.nonstop)
  }
}

extension Debuggee.Continuation {
  fileprivate init(_ payload: borrowing Span<UInt8>,
                   compatibility: CompatibilityMode,
                   debuggee: borrowing Debuggee) throws(GDBHandlerError) {
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
        try reader.operation(command, compatibility: compatibility)
    guard reader.empty else {
      throw .malformed
    }
    let selection: Debuggee.Thread.Selection = if split < payload.count {
      try Debuggee.Thread.Selection(payload.extracting((split + 1)...),
                                    debuggee: debuggee)
    } else {
      .all
    }
    self.init(selection: selection, operation: operation, signal: signal)
  }
}

extension GDBPacketReader {
  fileprivate mutating func operation(_ command: UInt8,
                                      compatibility: CompatibilityMode)
      throws(GDBHandlerError) -> (Debuggee.Continuation.Operation, CInt?) {
    switch command {
    case UInt8(ascii: "c"):
      return (.resume, nil)
    case UInt8(ascii: "s"):
      return (.step, nil)
    case UInt8(ascii: "t"):
      return (.stop, nil)
    case UInt8(ascii: "C"), UInt8(ascii: "S"):
      let value = try hex()
      guard let signal = compatibility.native(value) else {
        throw .malformed
      }
      let operation: Debuggee.Continuation.Operation =
          command == UInt8(ascii: "C") ? .resume : .step
      return (operation, signal)
    default:
      throw .unsupported
    }
  }
}

extension GDBPacketWriter {
  fileprivate mutating func resumed(nonstop: Bool) throws(GDBHandlerError)
      -> GDBPacketDisposition {
    guard nonstop else {
      return .none
    }
    try append("OK")
    return .reply
  }
}

extension GDBPacketReader {
  internal mutating func signal(compatibility: CompatibilityMode)
      throws(GDBHandlerError) -> (CInt, Debuggee.Address?) {
    let signal = try hex()
    guard let signal = compatibility.native(signal) else {
      throw .malformed
    }
    if consume(UInt8(ascii: ";")) {
      let address = try Debuggee.Address(rawValue: hex())
      guard empty else {
        throw .malformed
      }
      return (signal, address)
    }
    guard empty else {
      throw .malformed
    }
    return (signal, nil)
  }

  fileprivate mutating func process(selection: Debuggee.Thread.Selection,
                                    debuggee: borrowing Debuggee)
      throws(GDBHandlerError) -> ProcessIdentifier {
    guard empty == false else {
      return try selection.process(in: debuggee)
    }
    guard consume(UInt8(ascii: ";")) else {
      throw .malformed
    }
    let process = try ProcessIdentifier(rawValue: hex())
    guard empty, debuggee.contains(process) else {
      throw .debuggee(.process)
    }
    return process
  }

  fileprivate mutating func address() throws(GDBHandlerError)
      -> Debuggee.Address? {
    let address = empty ? nil : try Debuggee.Address(rawValue: hex())
    guard empty else {
      throw .malformed
    }
    return address
  }
}
