// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#elseif os(Windows)
internal import CRT
#endif
internal import Testing
@testable internal import DSX

@Suite
internal struct LogStreamTests {
  @Test
  internal func initialization() {
    #expect(DSX.enabled(.info, channel: .system) == false)
  }

  @Test
  internal func channel() {
    #expect(LogChannel(rawValue: "protocol") == .remote)
    #expect(LogChannel.remote.rawValue == "protocol")
    #expect(LogChannel(rawValue: "unknown") == nil)
  }

  @Test
  internal func storage() {
    let state =
        LogState(descriptor: TestSystem.error, owned: false, colour: false)
    #expect(state.buffer.capacity == 0)
  }

  @Test
  internal func deferred() {
    var evaluated = false
    let stream = LogStream(level: .off)
    func message() -> String {
      evaluated = true
      return "hidden"
    }
    stream(.critical, channel: .system, message())
    #expect(evaluated == false)
  }

  @Test
  internal func filtering() throws {
    let descriptors = try descriptors()
    let stream =
        LogStream(descriptor: descriptors.write, level: .info, colour: .never)
    stream(.trace, channel: .packet, "hidden")
    stream(.error, channel: .system, "failed")
    let output = try read(descriptors.read)
    #expect(output == "[error] [system] failed\n")
    TestSystem.close(descriptors.read)
    TestSystem.close(descriptors.write)
  }

  @Test
  internal func channels() throws {
    let descriptors = try descriptors()
    let stream = LogStream(descriptor: descriptors.write, level: .trace,
                           channels: LogChannel.packet.bit, colour: .never)
    stream(.trace, channel: .parser, "hidden")
    stream(.trace, channel: .packet, "visible")
    stream.select(LogChannel.parser.bit)
    stream(.trace, channel: .packet, "hidden")
    stream(.trace, channel: .parser, "selected")
    let output = try read(descriptors.read)
    #expect(output == "[trace] [packet] visible\n" +
                      "[trace] [parser] selected\n")
    TestSystem.close(descriptors.read)
    TestSystem.close(descriptors.write)
  }

  @Test
  internal func colour() throws {
    let descriptors = try descriptors()
    let stream =
        LogStream(descriptor: descriptors.write, level: .trace, colour: .always)
    stream(.warning, channel: .network, "slow")
    let output = try read(descriptors.read)
    #expect(output == "\u{001b}[33m[warning]\u{001b}[0m " +
                      "\u{001b}[36m[network] \u{001b}[0mslow\n")
    TestSystem.close(descriptors.read)
    TestSystem.close(descriptors.write)
  }

  @Test
  internal func packet() throws {
    let descriptors = try descriptors()
    let stream =
        LogStream(descriptor: descriptors.write, level: .trace, colour: .never)
    let packet: Array<UInt8> = [0x24, 0x71, 0x23]
    stream.bytes(packet.span, direction: .incoming)
    let output = try read(descriptors.read)
    #expect(output == "[trace] [packet] ← \"$q#\"\n")
    TestSystem.close(descriptors.read)
    TestSystem.close(descriptors.write)
  }

  @Test
  internal func escaping() throws {
    let descriptors = try descriptors()
    let stream =
        LogStream(descriptor: descriptors.write, level: .trace, colour: .never)
    let packet: Array<UInt8> =
        [0x58, 0x3a, 0x00, 0x09, 0x0a, 0x0d, 0x1b, 0x22, 0x5c, 0x7f,
         0x80]
    stream.bytes(packet.span, direction: .outgoing)
    let output = try read(descriptors.read)
    let expected =
        "[trace] [packet] → \"X:\\0\\t\\n\\r\\x1b\\\"\\\\\\x7f\\x80\"\n"
    #expect(output == expected)
    TestSystem.close(descriptors.read)
    TestSystem.close(descriptors.write)
  }

  @Test
  internal func empty() throws {
    let descriptors = try descriptors()
    let stream =
        LogStream(descriptor: descriptors.write, level: .trace, colour: .never)
    let packet = Array<UInt8>()
    stream.bytes(packet.span, direction: .outgoing)
    let output = try read(descriptors.read)
    #expect(output == "[trace] [packet] → ∅\n")
    TestSystem.close(descriptors.read)
    TestSystem.close(descriptors.write)
  }

#if !os(Windows)
  @Test
  internal func file() throws {
    var template = Array("/tmp/dsx-log.XXXXXX".utf8CString)
    let descriptor = template.withUnsafeMutableBufferPointer { buffer in
      TestSystem.temporary(buffer.baseAddress!)
    }
    guard descriptor >= 0 else {
      throw LogError.open(errno)
    }
    TestSystem.close(descriptor)
    let bytes = template.dropLast().map {
      UInt8(bitPattern: $0)
    }
    let path = String(decoding: bytes, as: UTF8.self)
    do {
      let stream =
          try LogStream(path: path, append: false, level: .trace,
                        colour: .never)
      stream(.notice, channel: .process, "created")
    }
    let input = TestSystem.open(path)
    guard input >= 0 else {
      throw LogError.open(errno)
    }
    let output = try read(input)
    #expect(output == "[notice] [process] created\n")
    TestSystem.close(input)
    TestSystem.unlink(path)
  }
#endif

  private func descriptors() throws -> (read: CInt, write: CInt) {
    var descriptors: Array<CInt> = [0, 0]
    guard TestSystem.pipe(&descriptors) == 0 else {
      throw LogError.open(errno)
    }
    return (descriptors[0], descriptors[1])
  }

  private func read(_ descriptor: CInt) throws -> String {
    var buffer = Array<UInt8>(repeating: 0, count: 512)
    let count = buffer.withUnsafeMutableBytes { bytes in
      TestSystem.read(descriptor, bytes.baseAddress, bytes.count)
    }
    guard count >= 0 else {
      throw LogError.open(errno)
    }
    return String(decoding: buffer.prefix(count), as: UTF8.self)
  }
}

private enum TestSystem {
  fileprivate static var error: CInt {
    STDERR_FILENO
  }

  fileprivate static func pipe(_ descriptors: UnsafeMutablePointer<CInt>)
      -> CInt {
#if os(Windows)
    _pipe(descriptors, 512, _O_BINARY)
#elseif os(anyAppleOS)
    Darwin.pipe(descriptors)
#elseif os(Android)
    Android.pipe(descriptors)
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
    Glibc.pipe(descriptors)
#endif
  }

  fileprivate static func read(_ descriptor: CInt,
                               _ buffer: UnsafeMutableRawPointer?,
                               _ count: Int) -> Int {
#if os(Windows)
    Int(_read(descriptor, buffer, UInt32(count)))
#elseif os(anyAppleOS)
    Darwin.read(descriptor, buffer, count)
#elseif os(Android)
    Android.read(descriptor, buffer, count)
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
    Glibc.read(descriptor, buffer, count)
#endif
  }

  fileprivate static func close(_ descriptor: CInt) {
#if os(Windows)
    _ = _close(descriptor)
#elseif os(anyAppleOS)
    _ = Darwin.close(descriptor)
#elseif os(Android)
    _ = Android.close(descriptor)
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
    _ = Glibc.close(descriptor)
#endif
  }

#if !os(Windows)
  fileprivate static func temporary(_ template: UnsafeMutablePointer<CChar>)
      -> CInt {
#if os(anyAppleOS)
    Darwin.mkstemp(template)
#elseif os(Android)
    Android.mkstemp(template)
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
    Glibc.mkstemp(template)
#endif
  }

  fileprivate static func open(_ path: String) -> CInt {
    path.withCString { path in
#if os(anyAppleOS)
      Darwin.open(path, O_RDONLY)
#elseif os(Android)
      Android.open(path, O_RDONLY)
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
      Glibc.open(path, O_RDONLY)
#endif
    }
  }

  fileprivate static func unlink(_ path: String) {
    path.withCString { path in
#if os(anyAppleOS)
      _ = Darwin.unlink(path)
#elseif os(Android)
      _ = Android.unlink(path)
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
      _ = Glibc.unlink(path)
#endif
    }
  }
#endif
}
