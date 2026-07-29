// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension PlatformSession {
  internal mutating func handle(_ packet: GDBPacketLeaf,
                                payload: borrowing Span<UInt8>,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    reap()
    switch packet {
    case .arguments, .run:
      if packet == .arguments {
        try launch.arguments(payload, writer: &writer)
      } else {
        try launch.run(payload)
      }
      do throws(Debuggee.Error) {
        _ = try spawn()
      } catch {
        error.log("failed to launch platform process")
        // The packet is implemented even when a requested launch option is not.
        if case .unsupported = error {
          throw .code(GDBErrorCode.failure)
        }
        throw .debuggee(error)
      }
      if packet == .run {
        try writer.append("OK")
      }
    case .qC:
      guard let process else {
        throw .code(GDBErrorCode.process)
      }
      try writer.append("QC")
      try writer.hex(process.rawValue)
    case .qLaunchSuccess:
      guard case .some = process else {
        throw .code(GDBErrorCode.process)
      }
      try writer.append("OK")
    case .qLaunchGDBServer:
      try launch(payload, writer: &writer)
    case .qPathComplete:
      try writer.completion(payload)
    case .qPlatform_mkdir:
      try GDBDirectoryRequest(payload).create(writer: &writer)
    case .qPlatform_chmod:
      try GDBDirectoryRequest(payload).permissions(writer: &writer)
    case .qPlatform_shell:
      try GDBShellRequest(payload).execute(writer: &writer)
    case .qUserName:
      let identifier = try UInt64(decimal: payload)
      try writer.encoded(translate(Host.user(identifier)))
    case .qGroupName:
      let identifier = try UInt64(decimal: payload)
      try writer.encoded(translate(Host.group(identifier)))
    case .qKillSpawnedProcess:
      try remove(payload, writer: &writer)
    case .qProcessInfo:
      try info(payload, writer: &writer)
    case .qQueryGDBServer:
      try query(writer: &writer)
    default:
      throw .unsupported
    }
    return .reply
  }
}
