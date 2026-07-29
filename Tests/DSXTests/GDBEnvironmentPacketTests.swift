// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct GDBEnvironmentPacketTests {
  @Test(arguments: ["", "A", "=B", "A\0B=C", "A=B\0C"])
  internal func invalid(_ value: String) {
    var launch = Debuggee.Launch()
    let bytes = Array(value.utf8)
    #expect(throws: GDBHandlerError.malformed) {
      try response { writer throws(GDBHandlerError) in
        try GDBEnvironmentPacket.raw(bytes.span, launch: &launch,
                                     writer: &writer)
      }
    }
    #expect(launch.environment.isEmpty)
  }

  @Test(arguments: ["", "413d42", "410042"])
  internal func unset(_ value: String) {
    var launch = Debuggee.Launch()
    let bytes = Array(value.utf8)
    #expect(throws: GDBHandlerError.malformed) {
      try response { writer throws(GDBHandlerError) in
        try GDBEnvironmentPacket.unset(bytes.span, launch: &launch,
                                       writer: &writer)
      }
    }
    #expect(launch.environment.isEmpty)
  }

  @Test
  internal func overrides() throws {
    var launch = Debuggee.Launch()
    for value in ["413d42", "413d", "413d433d44"] {
      let bytes = Array(value.utf8)
      let reply = try response { writer throws(GDBHandlerError) in
        try GDBEnvironmentPacket.handle(bytes.span, launch: &launch,
                                        writer: &writer)
      }
      #expect(reply == Array("OK".utf8))
      #expect(launch.environment.count == 1)
    }
    #expect(launch.environment == [
      Debuggee.Environment(name: "A", value: "C=D"),
    ])
    let bytes = Array("41".utf8)
    let reply = try response { writer throws(GDBHandlerError) in
      try GDBEnvironmentPacket.unset(bytes.span, launch: &launch,
                                     writer: &writer)
    }
    #expect(reply == Array("OK".utf8))
    #expect(launch.environment == [
      Debuggee.Environment(name: "A", value: nil),
    ])
  }
}

private typealias EnvironmentBody =
    (inout GDBPacketWriter) throws(GDBHandlerError) -> Void

private func response(_ body: EnvironmentBody) throws(GDBHandlerError)
    -> Array<UInt8> {
  var bytes = Array<UInt8>()
  try bytes.append(addingCapacity: 2) { output throws(GDBHandlerError) in
    var writer = GDBPacketWriter(output)
    do throws(GDBHandlerError) {
      try body(&writer)
    } catch {
      output = writer.finish()
      throw error
    }
    output = writer.finish()
  }
  return bytes
}
