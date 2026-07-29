// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct GDBTextTests {
  @Test(arguments: [("", "", ""), ("α", "ceb1", "α"),
                    ("🧵", "f09fa7b5", "🧵"), ("\n", "0a", "\\u000a"),
                    ("\"", "22", "\\\""), ("\\", "5c", "\\\\")])
  internal func encoding(_ value: String, _ hex: String, _ json: String)
      throws {
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 128) { bytes in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: bytes, initializedCount: 0))
      try writer.encoded(value)
      #expect(String(decoding: writer.output.span, as: UTF8.self) == hex)
      writer = GDBPacketWriter(OutputSpan(buffer: bytes, initializedCount: 0))
      try writer.json(value)
      #expect(String(decoding: writer.output.span, as: UTF8.self) == json)
    }
  }

  @Test(arguments: ["", "ThreadName", "worker α", "worker 🧵"])
  internal func append(_ value: String) {
    let expected = Array(value.utf8)
    for size in 0 ... expected.count {
      withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size) { bytes in
        var writer =
            GDBPacketWriter(OutputSpan(buffer: bytes, initializedCount: 0))
        var failure: GDBHandlerError?
        do throws(GDBHandlerError) {
          try writer.append(value.utf8Span.span)
        } catch {
          failure = error
        }
        if size == expected.count {
          #expect(failure == nil)
          #expect(writer.count == expected.count)
          #expect(Array(bytes.prefix(writer.count)) == expected)
        } else {
          #expect(failure == .capacity)
          #expect(writer.count == 0)
        }
      }
    }
  }

  @Test(arguments: ["00", "610062", "0", "gg"])
  internal func malformed(_ input: String) {
    #expect(throws: GDBHandlerError.malformed) {
      try String(hex: input.utf8Span.span)
    }
  }

  @Test(arguments: [("", ""), ("6162", "ab"), ("c3a9", "é")])
  internal func text(_ fixture: (String, String)) throws {
    #expect(try String(hex: fixture.0.utf8Span.span) == fixture.1)
  }

  @Test
  internal func binary() throws(GDBHandlerError) {
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: 3) { output throws(GDBHandlerError) in
      try output.decode("610062".utf8Span.span)
    }
    #expect(bytes == [97, 0, 98])
  }

  @Test(arguments: ["", "17x", "-1", "18446744073709551616"])
  internal func decimal(_ input: String) {
    #expect(throws: GDBHandlerError.malformed) {
      try UInt64(decimal: input.utf8Span.span)
    }
  }

  @Test(arguments: ["6,0,610062", "2,0,78,6,1,610062"])
  internal func arguments(_ input: String) {
    var launch = Debuggee.Launch(executable: "old", arguments: ["old"])
    var bytes = Array<UInt8>()
    #expect(throws: GDBHandlerError.malformed) {
      try bytes.append(addingCapacity: 16) { output throws(GDBHandlerError) in
        var writer = GDBPacketWriter(consume output)
        var failure: GDBHandlerError?
        do throws(GDBHandlerError) {
          try launch.arguments(input.utf8Span.span, writer: &writer)
        } catch {
          failure = error
        }
        output = writer.finish()
        if let failure {
          throw failure
        }
      }
    }
    #expect(launch.executable == "old")
    #expect(launch.arguments == ["old"])
  }
}
