// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemoteSessionState {
  @inline(never)
  internal mutating func handle(_ leaf: GDBPacketLeaf,
                                payload: borrowing Span<UInt8>,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    switch leaf {
    case .version:
      try writer.version()
    case .host:
      try writer.host()
    case .QSetMaxPacketSize:
      // LLDB includes framing and a terminating NUL in its packet buffer.
      try negotiation.limit(payload, overhead: 5, writer: &writer)
    case .QSetMaxPayloadSize:
      try negotiation.limit(payload, overhead: 0, writer: &writer)
    case .QEnableErrorStrings:
      try errors(payload, writer: &writer)
    case .symbol:
      try writer.symbol(payload)
    case .supported:
      try supported(payload, writer: &writer)
    case .process:
      try writer.process(payload)
    case .qfProcessInfo:
      try processes(payload, writer: &writer)
    case .qsProcessInfo:
      try processes(writer: &writer)
    case .QStartNoAckMode:
      _ = try negotiation.noack(writer: &writer)
    case .jSignalsInfo:
      try writer.signals(payload)
    default:
      throw .unsupported
    }
    return .reply
  }
}

internal func route(_ leaf: GDBPacketLeaf, payload: borrowing Span<UInt8>,
                    launch: inout Debuggee.Launch, files: inout FileSystem,
                    relative: Bool, writer: inout GDBPacketWriter)
    throws(GDBHandlerError) -> GDBPacketDisposition {
  switch leaf {
  case .aslr:
    try launch.aslr(payload, writer: &writer)
  case .QSetDetachOnError:
    try launch.detach(payload, writer: &writer)
  case .QSetSTDIOWindowSize:
    try launch.terminal(payload, writer: &writer)
  case .environment:
    try launch.environment(payload, writer: &writer)
  case .QEnvironmentReset:
    try launch.environment(reset: payload, writer: &writer)
  case .QEnvironmentUnset:
    try launch.environment(unset: payload, writer: &writer)
  case .stderr:
    try launch.error(payload, writer: &writer)
  case .stdin:
    try launch.input(payload, writer: &writer)
  case .stdout:
    try launch.output(payload, writer: &writer)
  case .QSetWorkingDir:
    try launch.directory(payload, writer: &writer)
  case .qGetWorkingDir:
    try launch.directory(writer: &writer)
  case .file:
    try files.handle(payload, directory: relative ? launch.directory : nil,
                     writer: &writer)
  case .module:
    try writer.emit(GDBModuleRequest(payload), directory: launch.directory)
  case .modules:
    var modules = try GDBModulesReader(payload.extracting(0...))
    try writer.emit(&modules, directory: launch.directory)
  default:
    throw .unsupported
  }
  return .reply
}
