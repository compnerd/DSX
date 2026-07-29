// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension PlatformSession {
  internal mutating func handle(_ packet: GDBPacketLeaf,
                                payload: borrowing Span<UInt8>,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    reap()
    switch packet {
    case .arguments:
      try GDBPlatformArgumentsPacket.handle(payload, server: &self,
                                            writer: &writer)
    case .qLaunchGDBServer:
      try GDBLaunchServerPacket.handle(payload, server: &self, writer: &writer)
    case .qPathComplete:
      try GDBPathCompletionPacket.handle(payload, writer: &writer)
    case .qPlatform_mkdir:
      try GDBPlatformDirectoryPacket.handle(payload, server: &self,
                                            writer: &writer)
    case .qPlatform_chmod:
      try GDBPlatformPermissionsPacket.handle(payload, server: &self,
                                              writer: &writer)
    case .qPlatform_shell:
      try GDBPlatformShellPacket.handle(payload, writer: &writer)
    case .qUserName:
      try GDBPlatformUserPacket.handle(payload, writer: &writer)
    case .qGroupName:
      try GDBPlatformGroupPacket.handle(payload, writer: &writer)
    case .qKillSpawnedProcess:
      try GDBKillServerPacket.handle(payload, server: &self, writer: &writer)
    case .qProcessInfo:
      try GDBPlatformProcessInfoPacket.handle(payload, server: &self,
                                              writer: &writer)
    case .qQueryGDBServer:
      try GDBQueryServerPacket.handle(server: self, writer: &writer)
    case .run:
      try GDBPlatformRunPacket.handle(payload, server: &self, writer: &writer)
    default:
      throw .unsupported
    }
    return .reply
  }
}
