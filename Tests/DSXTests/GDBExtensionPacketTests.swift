// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
#if os(Windows)
internal import WinSDK
#endif
@testable internal import DSX

@Suite
internal struct GDBExtensionPacketTests {
  private typealias Failure = GDBHandlerError

  @Test
  internal func launch() throws {
    var launch = Debuggee.Launch()
    let detach = try response { writer throws(Failure) in
      let payload = Array("1".utf8)
      _ = try GDBLaunchControlPacket.detach(payload.span, launch: &launch,
                                            writer: &writer)
    }
    #expect(detach == Array("OK".utf8))
    #expect(launch.detach)

    let terminal = try response { writer throws(Failure) in
      let payload = Array("cols=132;rows=43".utf8)
      _ = try GDBLaunchControlPacket.terminal(payload.span, launch: &launch,
                                              writer: &writer)
    }
    #expect(terminal == Array("OK".utf8))
    #expect(launch.terminal == Debuggee.TerminalSize(columns: 132, rows: 43))
  }

  @Test
  internal func signals() throws {
    let reply = try response { writer throws(Failure) in
      _ = try GDBSignalsPacket.handle(Span(), writer: &writer)
    }
    let text = String(decoding: reply, as: UTF8.self)
    #expect(text.hasPrefix("[{\"signo\":1,\"name\":\"SIGHUP\""))
    #expect(text.contains("{\"signo\":11,\"name\":\"SIGSEGV\""))
    #expect(text.hasSuffix("]"))
  }

  @Test
  internal func checksum() {
    var checksum = MD5Checksum()
    checksum.update(Array("abc".utf8).span)
    let digest = checksum.finish()
    let expected: InlineArray<16, UInt8> = [
      0x90, 0x01, 0x50, 0x98, 0x3c, 0xd2, 0x4f, 0xb0,
      0xd6, 0x96, 0x3f, 0x7d, 0x28, 0xe1, 0x7f, 0x72,
    ]
    for index in 0 ..< expected.count {
      #expect(digest[index] == expected[index])
    }
  }

  @Test
  internal func files() throws {
    let name = "dsx-packet-\(UInt64.random(in: 0 ... UInt64.max))"
    #if os(Windows)
    let path = try NativeFileSystem.resolve(name, working: temporary())
    #else
    let path = "/tmp/\(name)"
    #endif
    var files = FileSystem()
    let file = try files.open(path, options: [.write, .create, .exclusive],
                              mode: 0o600)
    let bytes = Array("abc".utf8)
    _ = try files.write(file, offset: 0, bytes: bytes.span)
    try files.close(file)
    defer {
      do throws(Debuggee.Error) {
        try NativeFileSystem.remove(path)
      } catch {
      }
    }
    let encoded = encode(path)
    let checksum = try response { writer throws(Failure) in
      let payload = Array("MD5:\(encoded)".utf8)
      _ = try GDBFilePacket.handle(payload.span, files: &files, writer: &writer)
    }
    #expect(checksum == Array("F,b04fd23c98500190727fe1287d3f96d6".utf8))

    let input = try files.open(path, options: [.read], mode: 0)
    let contents = try response { writer throws(Failure) in
      let handle = String(input.rawValue, radix: 16)
      let payload = Array("pread:\(handle),10,0".utf8)
      _ = try GDBFilePacket.handle(payload.span, files: &files, writer: &writer)
    }
    #expect(contents == Array("F3;abc".utf8))
    try files.close(input)

    let status = try response { writer throws(Failure) in
      let payload = Array("stat:\(encoded)".utf8)
      _ = try GDBFilePacket.handle(payload.span, files: &files, writer: &writer)
    }
    #expect(status.starts(with: Array("F40;".utf8)))
    #expect(status.count == 68)

    let selected = try response { writer throws(Failure) in
      let payload = Array("setfs:0".utf8)
      _ = try GDBFilePacket.handle(payload.span, files: &files, writer: &writer)
    }
    #expect(selected == Array("F0".utf8))

#if !os(Windows)
    let link = path + "-link"
    try NativeFileSystem.link(path, at: link)
    defer {
      do throws(Debuggee.Error) {
        try NativeFileSystem.remove(link)
      } catch {
      }
    }
    let reference = encode(link)
    let metadata = try response { writer throws(Failure) in
      let payload = Array("lstat:\(reference)".utf8)
      _ = try GDBFilePacket.handle(payload.span, files: &files, writer: &writer)
    }
    #expect(metadata.starts(with: Array("F40;".utf8)))
    #expect(metadata.count == 68)

    let destination = try response { writer throws(Failure) in
      let payload = Array("readlink:\(reference)".utf8)
      _ = try GDBFilePacket.handle(payload.span, files: &files, writer: &writer)
    }
    let expected = "F\(String(path.utf8.count, radix: 16));\(path)"
    #expect(destination == Array(expected.utf8))
#endif
  }

  @Test
  internal func core() throws {
    let absent = Array<UInt8>()
    #expect(try GDBSaveCorePacket.parse(absent.span) == nil)
    let encoded = Array(";path-hint:2f746d702f636f7265".utf8)
    #expect(try GDBSaveCorePacket.parse(encoded.span) == "/tmp/core")
  }
}

#if os(Windows)
private func temporary() throws(Debuggee.Error) -> String {
  var path = Array<WCHAR>(repeating: 0, count: 261)
  let count = path.withUnsafeMutableBufferPointer { path in
    GetTempPathW(DWORD(path.count), path.baseAddress)
  }
  guard count > 0, Int(count) < path.count else {
    throw .system(CInt(bitPattern: GetLastError()))
  }
  return String(decoding: path[0 ..< Int(count)], as: UTF16.self)
}
#endif

private func encode(_ value: String) -> String {
  var encoded = Array<UInt8>()
  encoded.reserveCapacity(value.utf8.count * 2)
  for byte in value.utf8 {
    encoded.append(GDBPacketWriter.hexadecimal(byte >> 4))
    encoded.append(GDBPacketWriter.hexadecimal(byte))
  }
  return String(decoding: encoded, as: UTF8.self)
}

private typealias GDBExtensionResponse =
    (inout GDBPacketWriter) throws(GDBHandlerError) -> Void

private func response(capacity size: Int = Configuration.PacketCapacity,
                      _ body: GDBExtensionResponse) throws -> Array<UInt8> {
  var response = Array<UInt8>()
  try response.append(addingCapacity: size) { output throws(GDBHandlerError) in
    var writer = GDBPacketWriter(output)
    let result: Result<Void, GDBHandlerError>
    do throws(GDBHandlerError) {
      try body(&writer)
      result = .success(())
    } catch {
      result = .failure(error)
    }
    output = writer.finish()
    try result.get()
  }
  return response
}
