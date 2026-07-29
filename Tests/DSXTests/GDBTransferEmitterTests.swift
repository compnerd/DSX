// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct GDBTransferEmitterTests {
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
    let response = try response(offset: offset, length: length) { emitter in
      emitter.append("abcdef")
    }
    #expect(response == expected)
  }

  @Test
  internal func escaping() throws {
    let response = try response(offset: 1, length: 3) { emitter in
      emitter.xml("&")
    }
    #expect(response == "!mamp")
  }

  @Test
  internal func capacity() {
    #expect(throws: GDBHandlerError.capacity) {
      try response(capacity: 1, offset: 0, length: 1) { emitter in
        emitter.append("a")
      }
    }
  }

  @Test
  internal func recovery() throws {
    let result = withUnsafeTemporaryAllocation(of: UInt8.self,
                                               capacity: 8) { buffer in
      var writer = GDBPacketWriter(OutputSpan(buffer: buffer,
                                              initializedCount: 0))
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
    var writer = GDBPacketWriter(OutputSpan(buffer: buffer,
                                            initializedCount: 0))
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
