// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct GDBBoundaryTests {
  @Test
  internal func lifetime() throws {
    let bytes = Array("abc;tail".utf8)
    var reader = GDBPacketReader(bytes.span)
    let field = try reader.field(UInt8(ascii: ";"))
    let prefix = reader.span(field)
    let suffix = reader.remaining()
    _ = try reader.take(reader.count)
    let empty = reader.empty
    #expect(empty)
    #expect(String(decoding: prefix, as: UTF8.self) == "abc")
    #expect(String(decoding: suffix, as: UTF8.self) == "tail")
    let returned = try tail(bytes.span)
    #expect(String(decoding: returned, as: UTF8.self) == "tail")
  }

  @_lifetime(copy bytes)
  private func tail(_ bytes: consuming Span<UInt8>) throws(GDBHandlerError)
      -> Span<UInt8> {
    var reader = GDBPacketReader(bytes)
    _ = try reader.field(UInt8(ascii: ";"))
    return reader.remaining()
  }

  @Test
  internal func delimiter() throws {
    let packet = "abc;;tail"
    var reader = GDBPacketReader(packet.utf8Span.span)
    #expect(try reader.field(UInt8(ascii: ";")) == 0 ..< 3)
    #expect(try reader.field(UInt8(ascii: ";")) == 4 ..< 4)
    #expect(throws: GDBHandlerError.malformed) {
      _ = try reader.field(UInt8(ascii: ";"))
    }
    let empty = reader.empty
    #expect(empty)
  }

  @Test(arguments: [";", ";;", ";thread:", ";thread:1;;", ";thread:1;x"])
  internal func suffix(_ payload: String) {
    var session = DebugSession()
    let state = GDBRemoteSessionState(compatibility: .lldb)
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 256) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      #expect(throws: GDBHandlerError.self) {
        try session.save(payload.utf8Span.span, state: state, writer: &writer)
      }
      #expect(throws: GDBHandlerError.self) {
        let request = "1" + payload
        try session.restore(request.utf8Span.span, state: state,
                            writer: &writer)
      }
    }
  }

  @Test(arguments: [("20", 0, 32), ("20", 5, 27), ("8", 5, 3), ("3", 0, 3)])
  internal func limits(_ fixture: (String, Int, Int)) throws {
    var negotiation = GDBRemoteNegotiation(capacity: 256)
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 256) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      try negotiation.limit(fixture.0.utf8Span.span, overhead: fixture.1,
                            writer: &writer)
      #expect(negotiation.payload == fixture.2)
    }
  }

  @Test(arguments: ["0", "1", "4", "5", "6", "7", "20x",
                    "ffffffffffffffff", ""])
  internal func invalid(_ payload: String) {
    var negotiation = GDBRemoteNegotiation(capacity: 256)
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 256) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      #expect(throws: GDBHandlerError.malformed) {
        try negotiation.limit(payload.utf8Span.span, overhead: 5,
                              writer: &writer)
      }
      #expect(negotiation.payload == 256)
      #expect(writer.count == 0)
    }
  }

  @Test(arguments: [("missing\0suffix", []), ("missing", ["a\0b"])])
  internal func launch(_ fixture: (String, Array<String>)) {
    #expect(throws: Debuggee.Error.process) {
      _ = try DebugSession(.launch(fixture.0, fixture.1))
    }
  }

  @Test
  internal func noack() {
    var negotiation = GDBRemoteNegotiation()
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 1) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      #expect(throws: GDBHandlerError.capacity) {
        _ = try negotiation.noack(writer: &writer)
      }
      #expect(negotiation.acknowledgements)
      #expect(negotiation.enabled.contains(.noack) == false)
    }
  }

  @Test
  internal func configuration() {
    var launch = Debuggee.Launch(directory: "original")
    var negotiation = GDBRemoteNegotiation(capacity: 256)
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 1) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      #expect(throws: GDBHandlerError.capacity) {
        try launch.directory("6e6577".utf8Span.span, writer: &writer)
      }
      #expect(launch.directory == "original")
      #expect(throws: GDBHandlerError.capacity) {
        try negotiation.limit("20".utf8Span.span, overhead: 0, writer: &writer)
      }
      #expect(negotiation.payload == 256)
    }
  }

  @Test
  internal func advertisement() {
    var state = GDBRemoteSessionState(compatibility: .lldb)
    state.negotiation.limit(32)
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 1) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      #expect(throws: GDBHandlerError.capacity) {
        try state.supported(Span<UInt8>(), writer: &writer)
      }
      #expect(state.negotiation.payload == 32)
      #expect(state.negotiation.advertised == false)
    }
  }

  @Test(arguments: [3, 4, 8, 256])
  internal func errors(_ capacity: Int) throws {
    let connection = try TestConnection()
    var core = GDBRemoteCore(channel: connection.connect(),
                             compatibility: .lldb, features: [.noack])
    core.state.negotiation.limit(capacity)
    core.state.messages = true
    try core.finish(.reply, failure: .debuggee(.process))
    let output = connection.output
    var cursor = 0
    let frame = try #require(GDBPacketFrame(output.span, cursor: &cursor))
    switch frame {
    case .packet(let range):
      #expect(range.count <= capacity)
      #expect(output[range.lowerBound] == UInt8(ascii: "E"))
      #expect(range.count == 3 ||
              output[range.lowerBound + 3] == UInt8(ascii: ";"))
      if capacity == 256 {
        #expect(range.count > 3)
      }
    case .control:
      Issue.record("expected an error packet")
    }
  }

  @Test(arguments: 0 ..< 4)
  internal func validation(_ field: Int) {
    var launch = Debuggee.Launch()
    let invalid = "prefix\0suffix"
    switch field {
    case 0: launch.directory = invalid
    case 1: launch.input = invalid
    case 2: launch.output = invalid
    default: launch.error = invalid
    }
    #expect(throws: Debuggee.Error.process) {
      try launch.validate()
    }
  }

  @Test(arguments: [(0, false), (1, false), (0, true), (1, true), (2, true)])
  internal func fields(_ fixture: (Int, Bool)) {
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: fixture.0) { raw in
      var writer = GDBPacketWriter(OutputSpan(buffer: raw, initializedCount: 0))
      #expect(throws: GDBHandlerError.capacity) {
        if fixture.1 {
          try writer.error(UInt8.max)
        } else {
          try writer.hex(UInt8.max)
        }
      }
      #expect(writer.count == 0)
    }
  }

  @Test
  internal func unicode() throws {
    let launch = Debuggee.Launch(executable: "程序", arguments: ["", "é"],
                                 directory: "目录", output: "输出")
    try launch.validate()
  }
}
