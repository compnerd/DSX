// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

@testable import DSX
import Testing

private struct TestRegisterState: ~Copyable {
  fileprivate var bytes: InlineArray<8, UInt8> = [0, 0, 0, 0, 0, 0, 0, 0]
}

private enum TestRegisters {
  internal typealias State = TestRegisterState

  internal static func snapshot(_ thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> TestRegisterState {
    TestRegisterState()
  }

  internal static func read(_ state: borrowing TestRegisterState,
                            register: RegisterIdentifier,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let description = RegisterDescription()
    guard let record = description.register(Int(register.rawValue)) else {
      throw .register
    }
    for index in 0 ..< ((record.bits + 7) / 8) {
      output.append(state.bytes[index % 8])
    }
  }

  internal static func write(_ state: inout TestRegisterState,
                             register: RegisterIdentifier,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  internal static func commit(_ state: consuming TestRegisterState,
                              thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) {}
}

private struct TestRegisterSession {}

private enum RegisterInfoPacket: GDBPacketHandler {
  internal typealias Context = TestRegisterSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qRegisterInfo", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout TestRegisterSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try GDBRegisterPacket.info(payload, registers: RegisterDescription(),
                               state: &state, writer: &writer)
    return .reply
  }
}

private enum RegisterFeaturesPacket: GDBPacketHandler {
  internal typealias Context = TestRegisterSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qXfer:features:read:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    .features
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout TestRegisterSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let request =
        try GDBTransferPacket.parse(.features, payload: payload, state: state)
    guard request.object == .features else {
      throw .unsupported
    }
    let reader = GDBPacketReader(payload.extracting(0...))
    guard reader.matches(request.annex, value: "target.xml") else {
      throw .unsupported
    }
    try GDBRegisterFeaturesPacket.write(offset: request.offset,
                                        length: request.length,
                                        registers: RegisterDescription(),
                                        compatibility: state.compatibility,
                                        writer: &writer)
    return .reply
  }
}

@Suite
internal struct RegisterTests {
  private typealias Failure = GDBHandlerError

  @Test
  internal func profile() throws {
    let profile = RegisterDescription()

    #if arch(arm64)
    #if os(Android) || os(Linux)
    #expect(profile.count == 162)
    #expect(profile.sets == 3)
    #expect(profile.features == 3)
    let last = try #require(profile.register(161))
    #expect(string(profile.name(last)) == "tpidr")
    #elseif os(anyAppleOS)
    #expect(profile.count == 164)
    #expect(profile.sets == 3)
    #expect(profile.features == 2)
    let far = try #require(profile.register(161))
    let esr = try #require(profile.register(162))
    let exception = try #require(profile.register(163))
    #expect(string(profile.name(far)) == "far")
    #expect(string(profile.name(esr)) == "esr")
    #expect(string(profile.name(exception)) == "exception")
    #else
    #expect(profile.count == 161)
    #expect(profile.sets == 2)
    #expect(profile.features == 2)
    let last = try #require(profile.register(160))
    #expect(string(profile.name(last)) == "d31")
    #endif
    #expect(profile.types == 4)
    #expect(profile.fields == 36)
    let first = try #require(profile.register(0))
    #expect(string(profile.name(first)) == "x0")
    #elseif arch(i386)
    #expect(profile.count == 41)
    #expect(profile.sets == 3)
    #expect(profile.features == 3)
    #expect(profile.types == 3)
    #expect(profile.fields == 30)
    let first = try #require(profile.register(0))
    let last = try #require(profile.register(40))
    #expect(string(profile.name(first)) == "eax")
    #expect(string(profile.name(last)) == "mxcsr")
    #elseif arch(x86_64)
    #expect(profile.count == 57)
    #expect(profile.sets == 3)
    #expect(profile.features == 3)
    #expect(profile.types == 3)
    #expect(profile.fields == 30)
    let first = try #require(profile.register(0))
    let last = try #require(profile.register(56))
    #expect(string(profile.name(first)) == "rax")
    #expect(string(profile.name(last)) == "mxcsr")
    #endif

    #expect(profile.register(-1) == nil)
    #expect(profile.register(profile.count) == nil)
    #if arch(arm64)
    #expect(profile.relation(0)?.rawValue == 0)
    #else
    #expect(profile.relation(0) == nil)
    #endif
    #expect(profile.feature(0) != nil)
    #expect(profile.set(0) != nil)
    #expect(profile.register(0, compatibility: .gdb)?.identifier.rawValue == 0)
    #expect(profile.register(0, compatibility: .lldb)?.identifier.rawValue == 0)
    #expect(profile.size(.gdb) > 0)
    #expect(profile.size(.gdb) == profile.size(.lldb))
  }

  #if os(Windows) && (arch(i386) || arch(x86_64))
  @Test
  internal func layout() throws(Debuggee.Error) {
    #if arch(i386)
    let expected: InlineArray<41, UInt32> = [
      0x040400b0, 0x040400ac, 0x040400a8, 0x040400a4, 0x040400c4,
      0x040400b4, 0x040400a0, 0x0404009c, 0x040400b8, 0x040400c0,
      0x040400bc, 0x040400c8, 0x04040098, 0x04040094, 0x04040090,
      0x0404008c, 0x0a0a00ec, 0x0a0a00fc, 0x0a0a010c, 0x0a0a011c,
      0x0a0a012c, 0x0a0a013c, 0x0a0a014c, 0x0a0a015c, 0x040200cc,
      0x040200ce, 0x040100d0, 0x040200d8, 0x040400d4, 0x040200e0,
      0x040400dc, 0x040200d2, 0x1010016c, 0x1010017c, 0x1010018c,
      0x1010019c, 0x101001ac, 0x101001bc, 0x101001cc, 0x101001dc,
      0x040400e4,
    ]
    #else
    let expected: InlineArray<57, UInt32> = [
      0x08080078, 0x08080090, 0x08080080, 0x08080088, 0x080800a8,
      0x080800b0, 0x080800a0, 0x08080098, 0x080800b8, 0x080800c0,
      0x080800c8, 0x080800d0, 0x080800d8, 0x080800e0, 0x080800e8,
      0x080800f0, 0x080800f8, 0x04040044, 0x04020038, 0x04020042,
      0x0402003e, 0x0402003c, 0x0402003a, 0x04020040, 0x0a0a0120,
      0x0a0a0130, 0x0a0a0140, 0x0a0a0150, 0x0a0a0160, 0x0a0a0170,
      0x0a0a0180, 0x0a0a0190, 0x04020100, 0x04020102, 0x04010104,
      0x0402010c, 0x04040108, 0x04020114, 0x04040110, 0x04020106,
      0x101001a0, 0x101001b0, 0x101001c0, 0x101001d0, 0x101001e0,
      0x101001f0, 0x10100200, 0x10100210, 0x10100220, 0x10100230,
      0x10100240, 0x10100250, 0x10100260, 0x10100270, 0x10100280,
      0x10100290, 0x04040034,
    ]
    #endif
    for index in 0 ..< expected.count {
      let identifier = RegisterIdentifier(rawValue: UInt32(index))
      let layout = try WindowsRegisters.layout(identifier)
      let packed = UInt32(layout.offset)
                 | UInt32(layout.native) << 16
                 | UInt32(layout.size) << 24
      #expect(packed == expected[index])
    }
    let invalid = RegisterIdentifier(rawValue: UInt32(expected.count))
    #expect(throws: Debuggee.Error.register) {
      try WindowsRegisters.layout(invalid)
    }
  }
  #endif

  @Test
  internal func snapshot() throws {
    let thread =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    let state = try TestRegisters.snapshot(thread)
    try TestRegisters.commit(state, thread: thread)
  }

  @Test
  internal func scalarbytes() throws {
    let bytes = Array<UInt8>([0x78, 0x56, 0x34, 0x12])
    let value = try RegisterBytes.value(bytes.span, as: UInt32.self)
    #expect(value == 0x12345678)

    let output =
        try withUnsafeTemporaryAllocation(of: UInt8.self,
                                          capacity: 4) { buffer in
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      try RegisterBytes.append(value, size: 4, into: &output)
      return Array(buffer[0 ..< output.count])
    }
    #expect(output == bytes)
  }

  @Test
  internal func offsetbytes() throws {
    var storage: InlineArray<4, UInt32> = [0, 0, 0, 0]
    let bytes = Array<UInt8>([0xef, 0xbe, 0xad, 0xde])
    try RegisterBytes.write(bytes.span, offset: 8, to: &storage)

    let output =
        try withUnsafeTemporaryAllocation(of: UInt8.self,
                                          capacity: 4) { buffer in
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      try RegisterBytes.append(storage, offset: 8, size: 4, into: &output)
      return Array(buffer[0 ..< output.count])
    }
    #expect(output == bytes)
  }

  @Test
  internal func extendedbytes() throws {
    var storage: InlineArray<2, UInt16> = [0, 0]
    let bytes = Array<UInt8>([0x34, 0x12, 0xfe, 0xca])
    try RegisterBytes.narrow(bytes.span, offset: 2, native: 2, size: 4,
                             to: &storage)

    let output =
        try withUnsafeTemporaryAllocation(of: UInt8.self,
                                          capacity: 4) { buffer in
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      try RegisterBytes.extend(storage, offset: 2, native: 2, size: 4,
                               into: &output)
      return Array(buffer[0 ..< output.count])
    }
    #expect(output == [0x34, 0x12, 0, 0])
  }

  @Test
  internal func info() throws {
    var session = TestRegisterSession()
    let first =
        try response(RegisterInfoPacket.self, packet: "qRegisterInfo0",
                     session: &session)
    let info = String(decoding: first, as: UTF8.self)
    #if arch(arm64)
    #expect(info.hasPrefix("name:x0;"))
    #expect(info.contains("generic:arg1;"))
    do {
      let bytes =
          try response(RegisterInfoPacket.self, packet: "qRegisterInfo23",
                       session: &session, compatibility: .lldb)
      let text = String(decoding: bytes, as: UTF8.self)
      #expect(text.hasPrefix("name:w1;"))
      #expect(text.contains("container-regs:1;"))
      #expect(text.contains("invalidate-regs:1;"))
    }
    do {
      let bytes =
          try response(RegisterInfoPacket.self, packet: "qRegisterInfo5f",
                       session: &session, compatibility: .lldb)
      let text = String(decoding: bytes, as: UTF8.self)
      #expect(text.hasPrefix("name:s0;"))
      #expect(text.contains("container-regs:3f;"))
      #expect(text.contains("invalidate-regs:3f,7f;"))
    }
    #if os(Android) || os(Linux)
    let bytes =
        try response(RegisterInfoPacket.self, packet: "qRegisterInfo44",
                     session: &session)
    let tls = String(decoding: bytes, as: UTF8.self)
    #expect(tls.hasPrefix("name:tpidr;"))
    #expect(tls.contains("generic:tp;"))
    #endif
    #elseif arch(i386)
    #expect(info.hasPrefix("name:eax;"))
    #expect(info.contains("generic:arg1;") == false)
    #elseif arch(x86_64)
    #expect(info.hasPrefix("name:rax;"))
    #expect(info.contains("generic:") == false)
    #if os(Windows)
    let argument = 2
    #else
    let argument = 5
    #endif
    let packet = "qRegisterInfo\(argument)"
    let bytes =
        try response(RegisterInfoPacket.self, packet: packet, session: &session)
    let details = String(decoding: bytes, as: UTF8.self)
    #if os(Windows)
    #expect(details.hasPrefix("name:rcx;"))
    #else
    #expect(details.hasPrefix("name:rdi;"))
    #endif
    #expect(details.contains("generic:arg1;"))
    #endif
  }

  @Test
  internal func features() throws {
    var session = TestRegisterSession()
    let capacity = String(Configuration.PacketCapacity, radix: 16)
    let packet = "qXfer:features:read:target.xml:0,\(capacity)"
    let response =
        try response(RegisterFeaturesPacket.self, packet: packet,
                     session: &session, compatibility: .lldb)
    let xml = String(decoding: response.dropFirst(), as: UTF8.self)
    #expect(response.first == UInt8(ascii: "l"))
    #expect(xml.contains("<target>"))
    #expect(xml.contains("<feature name="))
    #expect(xml.contains("<reg name="))
    let registers = RegisterDescription()
    for number in 0 ..< 2 {
      let register =
          try #require(registers.register(number, compatibility: .lldb))
      let marker = "\" regnum=\"\(number)\" offset=\"\(register.offset)\""
      #expect(xml.contains(marker))
    }
    #expect(xml.contains(" generic=\"pc\""))
    #if arch(arm64)
    #expect(xml.contains("<reg name=\"fp\" altname=\"x29\""))
    #expect(xml.contains("<flags id=\"cpsr_flags\" size=\"4\">"))
    #expect(xml.contains("<field name=\"N\" start=\"31\" end=\"31\"/>"))
    #expect(xml.contains("<reg name=\"cpsr\" altname=\"flags\""))
    #expect(xml.contains(" type=\"cpsr_flags\""))
    #expect(xml.contains("<enum id=\"rmode_enum\" size=\"4\">"))
    #expect(xml.contains("<evalue name=\"RZ\" value=\"3\"/>"))
    #expect(xml.contains("<flags id=\"fpsr_flags\" size=\"4\">"))
    #expect(xml.contains("<flags id=\"fpcr_flags\" size=\"4\">"))
    #expect(xml.contains("<field name=\"RMode\" start=\"22\" end=\"23\" " +
                         "type=\"rmode_enum\"/>"))
    #expect(xml.contains("<reg name=\"w1\""))
    #expect(xml.contains(" value_regnums=\"1\""))
    #expect(xml.contains(" invalidate_regnums=\"1\""))
    #endif
    #if arch(arm64) && (os(Android) || os(Linux))
    #expect(xml.contains("<reg name=\"tpidr\""))
    #expect(xml.contains(" generic=\"tp\""))
    #endif
  }
}

private func string(_ value: borrowing RegisterText) -> String {
  var bytes = Array<UInt8>()
  bytes.reserveCapacity(value.count)
  value.bytes { value in
    for index in 0 ..< value.count {
      bytes.append(value[index])
    }
  }
  return String(decoding: bytes, as: UTF8.self)
}

private func response<Handler>(_ handler: Handler.Type, packet: String,
                               session: inout Handler.Context,
                               compatibility: CompatibilityMode = .gdb) throws
    -> Array<UInt8>
    where Handler: GDBPacketHandler & ~Copyable {
  let bytes = Array(packet.utf8)
  var state =
      GDBRemoteSessionState(compatibility: compatibility, features: [.features])
  var response = Array<UInt8>()
  let size = Configuration.PacketCapacity
  try response.append(addingCapacity: size) { output throws(GDBHandlerError) in
    var writer = GDBPacketWriter(output)
    let result: Result<GDBPacketDisposition, any Error>
    do {
      let match = GDBPacketClassifier.classify(bytes.span)
      let payload = bytes.span.extracting(match.payload...)
      let disposition =
          try GDBPacketDispatch.handle(handler, payload: payload,
                                       session: &session, state: &state,
                                       writer: &writer)
      result = .success(disposition)
    } catch {
      result = .failure(error)
    }
    output = writer.finish()
    switch result {
    case .success:
      break
    case .failure(let error):
      guard let error = error as? GDBHandlerError else {
        throw .unexpected
      }
      throw error
    }
  }
  return response
}
