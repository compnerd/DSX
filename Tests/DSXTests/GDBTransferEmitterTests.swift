// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct GDBTransferEmitterTests {
  private typealias Failure = Debuggee.Error

  @Test
  internal func unicode() throws {
    let value = "α<&🧵"
    let plain = try response(capacity: 64, offset: 0,
                             length: 63) { emitter throws(Failure) in
      emitter.append(value)
    }
    #expect(plain == "!l" + value)
    let escaped = try response(capacity: 64, offset: 0,
                               length: 63) { emitter throws(Failure) in
      try emitter.xml(value)
    }
    #expect(escaped == "!lα&lt;&amp;🧵")
    let window = try response(offset: 2, length: 4) { emitter throws(Failure) in
      try emitter.xml(value)
    }
    #expect(window == "!m&lt;")
  }

  @Test(arguments: [
    (UInt64(0), UInt64(3), "!mabc"),
    (3, 3, "!ldef"),
    (6, 3, "!l"),
    (UInt64.max, 3, "!l"),
    (0, 0, "!m"),
    (0, UInt64.max, "!labcdef"),
  ])
  internal func window(_ offset: UInt64, _ length: UInt64,
                       _ expected: String) throws {
    let response = try response(offset: offset,
                                length: length) { emitter throws(Failure) in
      emitter.append("abcdef")
    }
    #expect(response == expected)
  }

  @Test
  internal func escaping() throws {
    let response = try response(offset: 1,
                                length: 3) { emitter throws(Failure) in
      try emitter.xml("&")
    }
    #expect(response == "!mamp")
  }

  @Test
  internal func whitespace() throws {
    let result = try response(capacity: 64, offset: 0,
                              length: 63) { emitter throws(Failure) in
      try emitter.path("a\t\r\nb")
    }
    #expect(result == "!la&#9;&#13;&#10;b")
    let window = try response(capacity: 16, offset: 3,
                              length: 7) { emitter throws(Failure) in
      try emitter.path("a\t\r\nb")
    }
    #expect(window == "!m9;&#13;")
  }

  @Test(arguments: [UInt32(0), 8, 11, 12, 14, 31, 0xfffe, 0xffff])
  internal func invalid(_ scalar: UInt32) {
    let text = String(Unicode.Scalar(scalar)!)
    #expect(throws: GDBHandlerError.debuggee(.state)) {
      try response(offset: 0, length: 4) { emitter throws(Failure) in
        try emitter.xml(text)
      }
    }
  }

  @Test(arguments: [UInt32(0x20), 0x7f, 0xd7ff, 0xe000, 0xfffd, 0x1fffe,
                    0x10ffff])
  internal func scalar(_ scalar: UInt32) throws {
    let text = String(Unicode.Scalar(scalar)!)
    let result = try response(offset: 0, length: 4) { emitter throws(Failure) in
      try emitter.xml(text)
    }
    #expect(result == "!l" + text)
  }

  @Test
  internal func capacity() {
    #expect(throws: GDBHandlerError.capacity) {
      try response(capacity: 1, offset: 0,
                   length: 1) { emitter throws(Failure) in
        emitter.append("a")
      }
    }
  }

  @Test
  internal func path() throws {
    let xml = try response(capacity: 128, offset: 0,
                           length: 100) { emitter throws(Failure) in
      try emitter.xml("/tmp/a\\b&c.so")
    }
    #expect(xml == "!l/tmp/a\\b&amp;c.so")
    let path = try response(capacity: 128, offset: 0,
                            length: 100) { emitter throws(Failure) in
      try emitter.path("/tmp/a\\b&c.so")
    }
#if os(Windows)
    #expect(path == "!l/tmp/a/b&amp;c.so")
#else
    #expect(path == "!l/tmp/a\\b&amp;c.so")
#endif
  }

  @Test
  internal func recovery() throws {
    let result = withUnsafeTemporaryAllocation(of: UInt8.self,
                                               capacity: 8) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      do throws(GDBHandlerError) {
        try writer.append("!")
        do throws(GDBHandlerError) {
          try writer.transfer(offset: 0,
                              length: 3) { emitter throws(Debuggee.Error) in
            emitter.append("abc")
            throw Debuggee.Error.memory
          }
          Issue.record("transfer swallowed the failure")
        } catch {
          #expect(error == .debuggee(.memory))
        }
        try writer.append(".")
        let value = String(decoding: writer.output.span, as: UTF8.self)
        return Result<String, GDBHandlerError>.success(value)
      } catch {
        return .failure(error)
      }
    }
    #expect(try result.get() == "!\0abc.")
  }
}

private func response(capacity: Int = 8, offset: UInt64, length: UInt64,
                      _ body: GDBTransferEmitterBody) throws(GDBHandlerError)
    -> String {
  let result = withUnsafeTemporaryAllocation(of: UInt8.self,
                                             capacity: capacity) { buffer in
    var writer =
        GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
    do throws(GDBHandlerError) {
      try writer.append("!")
      try writer.transfer(offset: offset, length: length, body)
      let value = String(decoding: writer.output.span, as: UTF8.self)
      return Result<String, GDBHandlerError>.success(value)
    } catch {
      return .failure(error)
    }
  }
  return try result.get()
}
