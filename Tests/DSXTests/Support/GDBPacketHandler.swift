// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

@testable import DSX

internal protocol GDBPacketHandler<Context>: ~Copyable, Sendable {
  associatedtype Context: ~Copyable

  static func handle(_ payload: borrowing Span<UInt8>, session: inout Context,
                     state: inout GDBRemoteSessionState,
                     writer: inout GDBPacketWriter) throws(GDBHandlerError)
      -> GDBPacketDisposition
}

internal enum GDBPacketDispatch {
  internal typealias State = GDBRemoteSessionState

  internal static func handle<Context, Handler>(_: Handler.Type,
                                                payload: borrowing Span<UInt8>,
                                                session: inout Context,
                                                state: inout State,
                                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition
      where Context: ~Copyable, Handler: GDBPacketHandler<Context> & ~Copyable {
    try Handler.handle(payload, session: &session, state: &state,
                       writer: &writer)
  }
}

internal typealias GDBTestTransferReader =
    (GDBTransferObject, ProcessIdentifier?, ProcessThreadIdentifier?, UInt64,
     Int, inout OutputSpan<UInt8>) throws(Debuggee.Error) -> ReadStatus

internal enum GDBTestTransfer {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              debuggee: borrowing Debuggee,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter,
                              read: GDBTestTransferReader)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let request =
        try GDBTransferRequest(.auxiliary, payload: payload.extracting(0...),
                               state: state)
    guard request.annex.isEmpty else {
      throw .unsupported
    }
    guard writer.output.freeCapacity > 0 else {
      throw .capacity
    }
    let (process, thread) = scope(debuggee, state: state)
    let requested = min(request.length, UInt64(Int.max))
    let limit = min(Int(requested), writer.output.freeCapacity - 1)
    let marker = writer.output.count
    try writer.append(0x00)
    let start = writer.output.count
    let status: ReadStatus
    do {
      status = try read(.auxiliary, process, thread, request.offset, limit,
                        &writer.output)
    } catch {
      throw .debuggee(error)
    }
    guard writer.output.count - start <= limit else {
      throw .capacity
    }
    writer.output[marker] = switch status {
    case .last: UInt8(ascii: "l")
    case .more: UInt8(ascii: "m")
    }
    return .reply
  }

  private static func scope(_ debuggee: borrowing Debuggee,
                            state: borrowing GDBRemoteSessionState)
      -> (ProcessIdentifier?, ProcessThreadIdentifier?) {
    let process = try? state.selection.general.process(in: debuggee)
    let selected = debuggee.resolve(state.selection.general)
    return (process, selected ?? state.selection.stopped)
  }
}

internal enum GDBAttachedPacket: GDBPacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try session.attached(payload, writer: &writer)
  }
}
internal enum GDBMultiBreakpointPacket: GDBPacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try session.breakpoints(payload, state: state, writer: &writer)
  }
}
internal enum GDBNonStopPacket: GDBPacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try session.nonstop(payload, state: &state, writer: &writer)
  }
}
internal enum GDBStopPacket: GDBPacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try session.status(payload, state: &state, writer: &writer)
  }
}
internal enum GDBThreadStopInfoPacket: GDBPacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try session.stopped(payload, state: state, writer: &writer)
  }
}
internal enum GDBThreadsInfoPacket: GDBPacketHandler {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try session.threads(payload, state: state, writer: &writer)
  }
}
internal enum GDBTransferPacket: GDBPacketHandler {
  internal typealias Context = DebugSession

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try session.transfer(.threads, payload: payload, state: &state,
                         writer: &writer)
  }
}

internal enum TestListThreadsPacket: GDBPacketHandler {
  internal typealias Context = DebugSession

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try state.negotiation.threads(writer: &writer)
  }
}

internal enum TestThreadSuffixPacket: GDBPacketHandler {
  internal typealias Context = DebugSession

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try state.negotiation.suffix(writer: &writer)
  }
}
