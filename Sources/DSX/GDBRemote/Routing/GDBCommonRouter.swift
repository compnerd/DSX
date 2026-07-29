// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBCommonRouter {
  internal static func remote(_ leaf: GDBPacketLeaf,
                              payload: borrowing Span<UInt8>,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    switch leaf {
    case .version:
      try GDBServerVersionPacket.handle(writer: &writer)
    case .host:
      try GDBHostInfoPacket.handle(writer: &writer)
    case .QSetMaxPacketSize:
      try GDBNegotiationPacket.packet(payload, state: &state, writer: &writer)
    case .QSetMaxPayloadSize:
      try GDBNegotiationPacket.payload(payload, state: &state, writer: &writer)
    case .QEnableErrorStrings:
      try GDBNegotiationPacket.errors(payload, state: &state, writer: &writer)
    case .symbol:
      try GDBSymbolPacket.handle(payload, writer: &writer)
    case .supported:
      try GDBSupportedPacket.handle(payload, state: &state, writer: &writer)
    case .process:
      try GDBProcessInfoPacket.handle(payload, state: &state, writer: &writer)
    case .qfProcessInfo:
      try GDBProcessEnumerationPacket.first(payload, state: &state,
                                            writer: &writer)
    case .qsProcessInfo:
      try GDBProcessEnumerationPacket.next(state: &state, writer: &writer)
    case .QStartNoAckMode:
      _ = try GDBNoAckPacket.handle(state: &state, writer: &writer)
    case .jSignalsInfo:
      try GDBSignalsPacket.handle(payload, writer: &writer)
    default:
      throw .unsupported
    }
    return .reply
  }

  internal static func session(_ leaf: GDBPacketLeaf,
                               payload: borrowing Span<UInt8>,
                               launch: inout Debuggee.Launch,
                               files: inout FileSystem, relative: Bool,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    switch leaf {
    case .aslr:
      try GDBASLRPacket.handle(payload, launch: &launch, writer: &writer)
    case .QSetDetachOnError:
      try GDBLaunchControlPacket.detach(payload, launch: &launch,
                                        writer: &writer)
    case .QSetSTDIOWindowSize:
      try GDBLaunchControlPacket.terminal(payload, launch: &launch,
                                          writer: &writer)
    case .environment:
      try GDBEnvironmentPacket.handle(payload, launch: &launch, writer: &writer)
    case .QEnvironmentReset:
      try GDBEnvironmentPacket.reset(payload, launch: &launch, writer: &writer)
    case .QEnvironmentUnset:
      try GDBEnvironmentPacket.unset(payload, launch: &launch, writer: &writer)
    case .stderr:
      try GDBStreamPacket.error(payload, launch: &launch, writer: &writer)
    case .stdin:
      try GDBStreamPacket.input(payload, launch: &launch, writer: &writer)
    case .stdout:
      try GDBStreamPacket.output(payload, launch: &launch, writer: &writer)
    case .QSetWorkingDir:
      try GDBWorkingDirectoryPacket.handle(payload, launch: &launch,
                                           writer: &writer)
    case .qGetWorkingDir:
      try GDBGetWorkingDirectoryPacket.handle(launch: launch, writer: &writer)
    case .file:
      try GDBFilePacket.handle(payload, files: &files,
                               working: relative ? launch.working : nil,
                               writer: &writer)
    case .module:
      try GDBModulePacket.handle(payload, working: launch.working,
                                 writer: &writer)
    case .modules:
      try GDBModulesPacket.handle(payload, working: launch.working,
                                  writer: &writer)
    default:
      throw .unsupported
    }
    return .reply
  }
}
