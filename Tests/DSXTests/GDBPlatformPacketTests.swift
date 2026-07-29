// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

private typealias Response =
    (inout GDBPacketWriter) throws(GDBHandlerError) -> Void

@Suite
internal struct GDBPlatformPacketTests {
  private typealias Failure = GDBHandlerError

  @Test
  internal func identity() throws {
    let identifier = try GDBPlatformIdentity.parse(Array("42".utf8).span)
    #expect(identifier == 42)
  }

  @Test
  internal func lifecycle() throws {
    let packet = Array(";host:::1;port:5000;".utf8)
    let request = try GDBLaunchServerPacket.parse(packet.span)
    #expect(request.host == "::1")
    #expect(request.port == 5000)

    let process = ProcessIdentifier(rawValue: 17)
    let child = HostProcess.Information(process: process, port: 5000)
    let launched = try response { writer throws(Failure) in
      try GDBLaunchServerPacket.write(child, writer: &writer)
    }
    #expect(launched == Array("pid:17;port:5000;".utf8))

    let parsed = try GDBKillServerPacket.parse(Array("17".utf8).span)
    #expect(parsed == child.process)

    let query = try response { writer throws(Failure) in
      try GDBQueryServerPacket.write(child, writer: &writer)
    }
    #expect(query == Array("[{\"port\":5000}]".utf8))
  }

  @Test
  internal func processes() throws {
    let empty = Array<UInt8>()
    var state = GDBRemoteSessionState(compatibility: .lldb)
    let packet = try response { writer throws(Failure) in
      _ = try GDBProcessEnumerationPacket.first(empty.span, state: &state,
                                                writer: &writer)
    }
    #expect(String(decoding: packet, as: UTF8.self).hasPrefix("pid:"))

    let filter = try response { writer throws(Failure) in
      try writer.append(":name:")
      try writer.encoded("__dsx_missing_process__")
      try writer.append(";")
    }
    let missing = try response { writer throws(Failure) in
      _ = try GDBProcessEnumerationPacket.first(filter.span, state: &state,
                                                writer: &writer)
    }
    #expect(missing == Array("E04".utf8))
    #expect(state.enumeration.filter == nil)
  }

  @Test
  internal func capability() throws {
    let supported = try response { writer throws(Failure) in
      _ = try GDBCapabilityPacket.handle(writer: &writer)
    }
    #expect(supported == Array("OK".utf8))

    let watchpoints = try response { writer throws(Failure) in
      _ = try GDBWatchpointPacket.handle(4, writer: &writer)
    }
    #expect(watchpoints == Array("num:4;".utf8))
  }

  @Test
  internal func shell() throws {
    let payload = Array("6563686f,5".utf8)
    let request = try GDBPlatformShellPacket.parse(payload.span)
    #expect(request.command == "echo")
    #expect(request.timeout == 5)
    #expect(request.working == nil)

    let response = try response { writer throws(Failure) in
      try writer.append("F,00000000,00000000,out")
      GDBPlatformShellPacket.write(.completed(.exited(7)), writer: &writer)
    }
    #expect(response == Array("F,00000007,00000000,out".utf8))
  }

  @Test
  internal func directory() throws {
    let payload = Array("1c0,2f746d702f6465627567".utf8)
    let request = try GDBPlatformDirectoryPacket.parse(payload.span)
    #expect(request.path == "/tmp/debug")
    #expect(request.mode == 0x01c0)

    let permissions = try GDBPlatformPermissionsPacket.parse(payload.span)
    #expect(permissions.path == "/tmp/debug")
    #expect(permissions.mode == 0x01c0)
  }

  @Test
  internal func modules() throws {
    var session = PlatformSession()
    let payload = Array("[]".utf8)
    let response = try response { writer throws(Failure) in
      _ = try GDBCommonRouter.session(.modules, payload: payload.span,
                                      launch: &session.launch,
                                      files: &session.files, relative: true,
                                      writer: &writer)
    }
    #expect(response == payload)
  }
}

private func response(_ body: Response) throws -> Array<UInt8> {
  var response = Array<UInt8>()
  let size = Configuration.PacketCapacity
  try response.append(addingCapacity: size) { output throws(GDBHandlerError) in
    var writer = GDBPacketWriter(consume output)
    var failure: GDBHandlerError?
    do throws(GDBHandlerError) {
      try body(&writer)
    } catch {
      failure = error
    }
    output = writer.finish()
    if let failure {
      throw failure
    }
  }
  return response
}
