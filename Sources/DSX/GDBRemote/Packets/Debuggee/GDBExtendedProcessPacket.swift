// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBKillProcessPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try process(payload, session: session, state: state)
    try translate(session.terminate(process))
    state.termination = .extended(process)
  }
}

private func process(_ payload: borrowing Span<UInt8>,
                     session: borrowing DebugSession,
                     state: borrowing GDBRemoteSessionState)
    throws(GDBHandlerError) -> ProcessIdentifier {
  guard payload.count > 0 else {
    return try GDBPacketScope.process(state.selection.resume,
                                      debuggee: session.debuggee)
  }
  var reader = GDBPacketReader(payload.extracting(0...))
  guard reader.consume(UInt8(ascii: ";")) else {
    throw .malformed
  }
  let process = try ProcessIdentifier(rawValue: reader.hex())
  guard reader.empty, session.debuggee.contains(process) else {
    throw .debuggee(.process)
  }
  return process
}

internal enum GDBAttachNamePacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try GDBNamedAttach.attach(payload, policy: .now, session: &session,
                              state: &state)
  }
}

internal enum GDBAttachOrWaitPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try GDBNamedAttach.attach(payload, policy: .either, session: &session,
                              state: &state)
  }
}

internal enum GDBAttachWaitPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try GDBNamedAttach.attach(payload, policy: .future, session: &session,
                              state: &state)
  }
}

internal enum GDBAttachPolicy: Equatable {
  case either
  case future
  case now
}

internal enum GDBNamedAttachPlan {
  case attach(ProcessIdentifier)
  case queue(String, existing: Bool)
}

internal enum GDBNamedAttach {
  internal static func attach(_ payload: borrowing Span<UInt8>,
                              policy: GDBAttachPolicy,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState)
      throws(GDBHandlerError) {
    let plan = try plan(payload, policy: policy)
    switch plan {
    case .attach(let process):
      try translate(session.attach(process))
    case .queue(let name, let existing):
      try translate(session.queue(name, existing: existing))
    }
  }

  internal static func plan(_ payload: borrowing Span<UInt8>,
                            policy: GDBAttachPolicy) throws(GDBHandlerError)
      -> GDBNamedAttachPlan {
    let name = try name(payload)
    if policy == .future {
      return .queue(name, existing: true)
    }
    let process = try translate(process(name))
    guard let process else {
      guard policy == .either else {
        throw .debuggee(.process)
      }
      return .queue(name, existing: false)
    }
    return .attach(process)
  }

  internal static func name(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) -> String {
    guard payload.count > 0 else {
      throw .malformed
    }
    return try GDBPacketReader.string(payload)
  }
}
