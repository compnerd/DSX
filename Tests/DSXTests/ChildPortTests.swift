// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct ChildPortTests {
  @Test
  internal func parses() throws {
    var port = ChildPort()
    #expect(try port.consume(UInt8(ascii: "1")) == nil)
    #expect(try port.consume(UInt8(ascii: "2")) == nil)
    #expect(try port.consume(UInt8(ascii: "3")) == nil)
    #expect(try port.consume(UInt8(ascii: "\n")) == 123)
  }

  @Test
  internal func rejects() throws {
    var empty = ChildPort()
    #expect(throws: Debuggee.Error.state) {
      try empty.consume(UInt8(ascii: "\n"))
    }
    var malformed = ChildPort()
    #expect(throws: Debuggee.Error.state) {
      try malformed.consume(UInt8(ascii: "x"))
    }
    var overflow = ChildPort()
    for byte in "65536".utf8 {
      _ = try overflow.consume(byte)
    }
    #expect(throws: Debuggee.Error.state) {
      try overflow.consume(UInt8(ascii: "\n"))
    }
  }
}
