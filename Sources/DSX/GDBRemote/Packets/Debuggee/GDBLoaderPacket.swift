// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBLoaderPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: borrowing DebugSession,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    try writer.emit(translate(process.loader))
  }
}

private func name(_ state: Debuggee.Loader.State) -> StaticString {
  switch state {
  case .absent: "dyld_process_state_not_started"
  case .loaded: "dyld_process_state_dyld_initialized"
  case .aborted: "dyld_process_state_terminated_before_inits"
  case .ready: "dyld_process_state_libSystem_initialized"
  case .initializing: "dyld_process_state_running_initializers"
  case .running: "dyld_process_state_program_running"
  case .terminated: "dyld_process_state_dyld_terminated"
  }
}

extension GDBPacketWriter {
  internal mutating func emit(_ loader: borrowing Debuggee.Loader)
      throws(GDBHandlerError) {
    try append("{\"process_state_value\":")
    try decimal(UInt64(loader.value))
    if let state = loader.state {
      try append(",\"process_state string\":\"")
      try append(name(state))
      try append(UInt8(ascii: "\""))
    }
    try append(UInt8(ascii: "}"))
  }
}
