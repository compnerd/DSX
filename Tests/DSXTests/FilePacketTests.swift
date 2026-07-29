// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct FilePacketTests {
  @Test(arguments: [0, 1])
  internal func empty(_ size: Int) throws {
    var files = FileSystem()
    let file = try files.open(#filePath, options: [.read], mode: 0)
    let buffer = UnsafeMutableBufferPointer<UInt8>(start: nil, count: 0)
    var output = OutputSpan(buffer: buffer, initializedCount: 0)
    try files.read(file, offset: 0, size: size, into: &output)
    #expect(output.count == 0)
    #expect(throws: Debuggee.Error.file(.descriptor)) {
      try files.read(FileIdentifier(rawValue: 0), offset: 0, size: size,
                     into: &output)
    }
    #expect(throws: Debuggee.Error.self) {
      try files.read(file, offset: UInt64.max, size: size, into: &output)
    }
  }

  @Test(arguments: ["", "-missing", "-missing/child"])
  internal func exists(_ suffix: String) throws {
    var files = FileSystem()
    let path = #filePath + suffix
    let encoded = path.utf8.map { byte in
      let digits = String(byte, radix: 16)
      return digits.count == 1 ? "0" + digits : digits
    }.joined()
    let reply = try response("exists:" + encoded, files: &files)
    #expect(reply == Array((suffix.isEmpty ? "F,1" : "F,0").utf8))
  }

  @Test(arguments: [0, 4])
  internal func prefix(_ count: Int) throws {
    var files = FileSystem()
    let file = try files.open(#filePath, options: [.read], mode: 0)
    let identifier = String(file.rawValue, radix: 16)
    let reply = try response("pread:\(identifier),\(count),0", files: &files)
    let expected = count == 0 ? "F0;" : "F4;// C"
    #expect(reply == Array(expected.utf8))
  }

  @Test
  internal func status() throws {
    var files = FileSystem()
    let file = try files.open(#filePath, options: [.read], mode: 0)
    let identifier = String(file.rawValue, radix: 16)
    let reply = try response("fstat:" + identifier, files: &files)
    #expect(reply.count == 68)
    #expect(reply.starts(with: "F40;".utf8))
  }
}

private func response(_ request: String, files: inout FileSystem)
    throws(GDBHandlerError) -> Array<UInt8> {
  let payload = Array(request.utf8)
  var bytes = Array<UInt8>()
  try bytes.append(addingCapacity: 256) { output throws(GDBHandlerError) in
    var writer = GDBPacketWriter(output)
    do throws(GDBHandlerError) {
      try files.handle(payload.span, writer: &writer)
    } catch {
      output = writer.finish()
      throw error
    }
    output = writer.finish()
  }
  return bytes
}
