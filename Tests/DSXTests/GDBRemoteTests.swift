// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

private let kCapacity = String(Configuration.PacketCapacity, radix: 16)

private protocol TestRouter {
  associatedtype Context: ~Copyable
  static var features: GDBRemoteFeatures { get }

  static func dispatch(_ leaf: GDBPacketLeaf, payload: borrowing Span<UInt8>,
                       session: inout Context,
                       state: inout GDBRemoteSessionState,
                       writer: inout GDBPacketWriter) throws(GDBHandlerError)
      -> GDBPacketDisposition
}

/// Exercises the shared packet core with synthetic responses.
private struct TestRemote<Router: TestRouter>:
    ~Copyable {
  fileprivate var core: GDBRemoteCore
  fileprivate var session: Router.Context

  fileprivate init(channel: consuming ConnectionTransport,
                   session: consuming Router.Context, router _: Router.Type,
                   compatibility: CompatibilityMode,
                   capacity: Int = Configuration.PacketCapacity) {
    self.session = consume session
    core = GDBRemoteCore(channel: consume channel, compatibility: compatibility,
                         features: Router.features, capacity: capacity)
  }

  fileprivate mutating func step() throws(GDBRemoteError) {
    guard let exchange =
        try core.packet({ match, data, state, sink throws(GDBHandlerError) in
      if match.route == .remote {
        return try GDBCommonRouter.remote(match.leaf, payload: data,
                                          state: &state, writer: &sink)
      }
      return try Router.dispatch(match.leaf, payload: data, session: &session,
                                 state: &state, writer: &sink)
    }) else {
      return
    }
    guard try core.acknowledge(exchange.message, exchange.acknowledge) else {
      return
    }
    try core.finish(exchange.disposition, failure: exchange.failure,
                    interrupt: exchange.message == .interrupt)
  }
}

private struct TestSession {
  fileprivate var queries = 0
}

private enum TestTransfer {
  internal static func read(_ object: GDBTransferObject,
                            process _: ProcessIdentifier?,
                            thread _: ProcessThreadIdentifier?, offset: UInt64,
                            limit: Int, into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> ReadStatus {
    guard object == .auxiliary, offset <= 4 else {
      throw .unsupported
    }
    let value = Array("test".utf8)
    let start = Int(offset)
    let count = min(limit, value.count - start)
    for index in 0 ..< count {
      output.append(value[start + index])
    }
    return start + count == value.count ? .last : .more
  }
}

private struct TransferSession: ~Copyable, Sendable {
  internal var debuggee = Debuggee()
}

private enum TestTransferPacket: GDBPacketHandler {
  internal typealias Context = TransferSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qXfer:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    [.auxiliary]
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout TransferSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let read: GDBTestTransferReader = { kind, pid, tid, base, size, output in
      try TestTransfer.read(kind, process: pid, thread: tid, offset: base,
                            limit: size, into: &output)
    }
    return try GDBTestTransfer.handle(payload, debuggee: session.debuggee,
                                      state: state, writer: &writer, read: read)
  }
}

private enum StatePacket: GDBPacketHandler {
  internal typealias Context = TestSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qState")
  }

  internal static var features: GDBRemoteFeatures {
    [.multiprocess]
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout Context,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try writer.hex(UInt64(state.negotiation.payload))
    if state.negotiation.enabled.contains(.multiprocess) {
      try writer.append(";negotiated")
    }
    return .reply
  }
}

private enum StubPacket: GDBPacketHandler {
  internal typealias Context = TestSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qTarget")
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout Context,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    session.queries += 1
    try writer.hex(UInt64(session.queries))
    return .reply
  }
}

private enum StateRouter: TestRouter {
  internal typealias Context = TestSession

  internal static var features: GDBRemoteFeatures {
    [.binary, .events, .execute, .executable, .hwbreak, .map, .multiprocess,
     .noack, .options, .randomization, .reset, .swbreak, .threads, .unset,
     .vcont]
  }

  internal static func dispatch(_ leaf: GDBPacketLeaf,
                                payload packet: borrowing Span<UInt8>,
                                session: inout Context,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard packet.count > 2 else {
      return try fallback(packet, state: &state, writer: &writer)
    }
    let payload = packet.extracting(StatePacket.packet.count...)
    return switch (packet[0], packet[1], packet[2]) {
    case (UInt8(ascii: "q"), UInt8(ascii: "S"), UInt8(ascii: "t"))
        where StatePacket.packet.matches(packet):
      try GDBPacketDispatch.handle(StatePacket.self, payload: payload,
                                   session: &session, state: &state,
                                   writer: &writer)
    default:
      try fallback(packet, state: &state, writer: &writer)
    }
  }
}

private enum DefaultRouter: TestRouter {
  internal typealias Context = DebugSession

  internal static var features: GDBRemoteFeatures {
    [.noack]
  }

  internal static func dispatch(_ leaf: GDBPacketLeaf,
                                payload packet: borrowing Span<UInt8>,
                                session: inout Context,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try fallback(packet, state: &state, writer: &writer)
  }
}

private enum GrowthRouter: TestRouter {
  internal typealias Context = DebugSession

  internal static var features: GDBRemoteFeatures {
    [.libraries]
  }

  internal static func dispatch(_ leaf: GDBPacketLeaf,
                                payload _: borrowing Span<UInt8>,
                                session _: inout Context,
                                state _: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard leaf == .libraries else {
      throw .unsupported
    }
    let bytes = Array(repeating: UInt8(ascii: "a"), count: 256)
    try writer.append(bytes.span)
    return .reply
  }
}

private enum OverflowRouter: TestRouter {
  internal typealias Context = DebugSession

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func dispatch(_: GDBPacketLeaf,
                                payload _: borrowing Span<UInt8>,
                                session _: inout Context,
                                state _: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let bytes = Array(repeating: UInt8(ascii: "a"), count: 256)
    try writer.append(bytes.span)
    return .reply
  }
}

private enum StateOnlyRouter: TestRouter {
  internal typealias Context = TestSession

  internal static var features: GDBRemoteFeatures {
    StatePacket.features
  }

  internal static func dispatch(_ leaf: GDBPacketLeaf,
                                payload packet: borrowing Span<UInt8>,
                                session: inout Context,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard packet.count > 2 else {
      throw .unsupported
    }
    let payload = packet.extracting(StatePacket.packet.count...)
    return switch (packet[0], packet[1], packet[2]) {
    case (UInt8(ascii: "q"), UInt8(ascii: "S"), UInt8(ascii: "t"))
        where StatePacket.packet.matches(packet):
      try GDBPacketDispatch.handle(StatePacket.self, payload: payload,
                                   session: &session, state: &state,
                                   writer: &writer)
    default:
      throw .unsupported
    }
  }
}

private enum StubRouter: TestRouter {
  internal typealias Context = TestSession

  internal static var features: GDBRemoteFeatures {
    StubPacket.features.union(.noack)
  }

  internal static func dispatch(_ leaf: GDBPacketLeaf,
                                payload packet: borrowing Span<UInt8>,
                                session: inout Context,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard packet.count > 1 else {
      return try fallback(packet, state: &state, writer: &writer)
    }
    let payload = packet.extracting(StubPacket.packet.count...)
    return switch (packet[0], packet[1]) {
    case (UInt8(ascii: "q"), UInt8(ascii: "T"))
        where StubPacket.packet.matches(packet):
      try GDBPacketDispatch.handle(StubPacket.self, payload: payload,
                                   session: &session, state: &state,
                                   writer: &writer)
    default:
      try fallback(packet, state: &state, writer: &writer)
    }
  }
}

private enum FailureRouter: TestRouter {
  internal typealias Context = TestSession

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func dispatch(_ leaf: GDBPacketLeaf,
                                payload: borrowing Span<UInt8>,
                                session: inout Context,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    throw .debuggee(.access)
  }
}

private enum MalformedRouter: TestRouter {
  internal typealias Context = TestSession

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func dispatch(_ leaf: GDBPacketLeaf,
                                payload: borrowing Span<UInt8>,
                                session: inout Context,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    throw .malformed
  }
}

private enum TransferRouter: TestRouter {
  internal typealias Context = TransferSession

  internal static var features: GDBRemoteFeatures {
    GDBRemoteFeatures.noack.union(TestTransferPacket.features)
  }

  internal static func dispatch(_ leaf: GDBPacketLeaf,
                                payload packet: borrowing Span<UInt8>,
                                session: inout Context,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard leaf == .transfer(.auxiliary) else {
      return try fallback(packet, state: &state, writer: &writer)
    }
    return try GDBPacketDispatch.handle(TestTransferPacket.self,
                                        payload: packet, session: &session,
                                        state: &state, writer: &writer)
  }
}

private func fallback(_ packet: borrowing Span<UInt8>,
                      state: inout GDBRemoteSessionState,
                      writer: inout GDBPacketWriter) throws(GDBHandlerError)
    -> GDBPacketDisposition {
  let match = GDBPacketClassifier.classify(packet)
  if match.leaf == .QStartNoAckMode {
    return try GDBNoAckPacket.handle(state: &state, writer: &writer)
  }
  if match.leaf == .supported {
    let payload = packet.extracting(match.payload...)
    try GDBSupportedPacket.handle(payload, state: &state, writer: &writer)
    return .reply
  }
  throw .unsupported
}

private func extract(_ frame: inout Array<UInt8>, cursor: inout Int,
                     checksum: Bool = true) throws(GDBPacketError)
    -> Range<Int>? {
  var input = frame.mutableSpan
  guard let frame = try GDBPacketFraming.extract(&input, cursor: &cursor,
                                                 checksum: checksum) else {
    return nil
  }
  return switch frame {
  case .control(let range), .packet(let range): range
  }
}

private func decode(_ frame: inout Array<UInt8>, _ range: Range<Int>,
                    encoding: GDBPacketEncoding) throws(GDBPacketError)
    -> Range<Int> {
  var input = frame.mutableSpan
  return try GDBPacketFraming.decode(range, input: &input, encoding: encoding)
}

@Suite
internal struct GDBRemoteTests {
  @Test
  internal func close() throws {
    let storage = try TestConnection([])
    var remote = GDBRemote(channel: storage.connect(), session: DebugSession(),
                           compatibility: .lldb)
    remote.session.state = .waiting((name: "process", excluded: []))
    remote.close(.failure)
    if case .absent = remote.session.state {
    } else {
      Issue.record("closing did not reset the session")
    }
    remote.session.state = .waiting((name: "sentinel", excluded: []))
    remote.close(.normal)
    if case .waiting = remote.session.state {
    } else {
      Issue.record("closing twice repeated session cleanup")
    }
  }

  @Test
  internal func framing() throws {
    let payload: Array<UInt8> = [
      0x71, 0x23, 0x24, 0x7d, 0x2a,
    ]
    let expected: Array<UInt8> = [
      UInt8(ascii: "$"), 0x71,
      UInt8(ascii: "}"), 0x03,
      UInt8(ascii: "}"), 0x04,
      UInt8(ascii: "}"), 0x5d,
      UInt8(ascii: "}"), 0x0a,
      UInt8(ascii: "#"), UInt8(ascii: "d"), UInt8(ascii: "3"),
    ]
    var generated = Array<UInt8>()
    let capacity = GDBPacketFraming.capacity(payload.span, encoding: .binary)
    generated.append(addingCapacity: capacity) { output in
      GDBPacketFraming.frame(payload.span, encoding: .binary, output: &output)
    }
    #expect(generated == expected)
    var frame = payload
    for _ in payload.count ..< expected.count {
      frame.append(0)
    }
    do {
      var output = frame.mutableSpan
      GDBPacketFraming.frame(payload.count, encoding: .binary, output: &output)
    }
    #expect(frame == expected)

    var cursor = 0
    let range = try extract(&frame, cursor: &cursor)
    let wire = try #require(range)
    let extracted = try decode(&frame, wire, encoding: .binary)
    let message = frame.span.extracting(extracted)
    #expect(message.count == payload.count)
    for index in 0 ..< message.count {
      #expect(message[index] == payload[index])
    }
    #expect(cursor == frame.count)
  }

  @Test
  internal func json() throws {
    let payload = Array("[{\"signo\":19}]".utf8)
    var frame = Array<UInt8>()
    let capacity = GDBPacketFraming.capacity(payload.span, encoding: .text)
    frame.append(addingCapacity: capacity) { output in
      GDBPacketFraming.frame(payload.span, encoding: .text, output: &output)
    }
    let marker = try #require(frame.firstIndex(of: UInt8(ascii: "}")))
    #expect(frame[marker + 1] == UInt8(ascii: "]"))

    var cursor = 0
    let range = try extract(&frame, cursor: &cursor)
    let extracted = try #require(range)
    #expect(Array(frame[extracted]) == payload)
    #expect(cursor == frame.count)
  }

  @Test
  internal func logical() throws {
    let payload = Array("jModulesInfo:[{\"file\":\"a\"}]".utf8)
    let storage = try TestConnection(frame(payload.span, encoding: .binary))
    var channel = GDBPacketChannel(channel: storage.connect())
    var received = Array<UInt8>()
    func receive(_ message: GDBChannelMessage, _ match: GDBPacketMatch,
                 _ packet: borrowing Span<UInt8>,
                 _ response: inout GDBPacketBuffer) {
      #expect(match.leaf == .modules)
      for index in 0 ..< packet.count {
        received.append(packet[index])
      }
    }
    try channel.receive(receive)
    #expect(received == payload)
  }

  @Test
  internal func singular() throws {
    let payload = [UInt8(ascii: "+")]
    let storage = try TestConnection(frame(payload.span))
    var channel = GDBPacketChannel(channel: storage.connect())
    var packet = false
    try channel.receive { message, _, data, _ in
      if case .packet = message {
        packet = true
      }
      #expect(data.count == payload.count)
      for index in 0 ..< data.count {
        #expect(data[index] == payload[index])
      }
    }
    #expect(packet)
  }

  @Test
  internal func multimemory() throws {
    let request = Array("MultiMemRead:ranges:1000,4;".utf8)
    let match = GDBPacketClassifier.classify(request.span)
    #expect(match.leaf == .MultiMemRead)
    #expect(match.response == .binary)

    let storage = try TestConnection([])
    var channel = GDBPacketChannel(channel: storage.connect())
    let payload = Array<UInt8>([UInt8(ascii: "4"), UInt8(ascii: ";"),
                               UInt8(ascii: "#"), UInt8(ascii: "$"),
                               UInt8(ascii: "}"), UInt8(ascii: "*")])
    let body: GDBResponse = { writer throws(GDBHandlerError) in
        try writer.append(payload.span)
    }
    let result = channel.response(payload.count, encoding: match.response, body)
    guard case .success = result else {
      Issue.record("multi-memory response failed")
      return
    }
    try channel.send()
    #expect(storage.output == frame(payload.span, encoding: .binary))
  }

  @Test
  internal func brace() throws {
    let payload = Array("jGetSharedCacheInfo:{}".utf8)
    var checksum: UInt8 = 0
    for byte in payload {
      checksum &+= byte
    }
    var frame = [UInt8(ascii: "$")] + payload
    frame.append(UInt8(ascii: "#"))
    frame.append(GDBPacketWriter.hexadecimal(checksum >> 4))
    frame.append(GDBPacketWriter.hexadecimal(checksum))

    var cursor = 0
    let range = try extract(&frame, cursor: &cursor)
    let extracted = try #require(range)
    let match = GDBPacketClassifier.classify(frame.span.extracting(extracted))
    #expect(match.request == .text)
    #expect(match.response == .binary)
    let decoded = try decode(&frame, extracted, encoding: match.request)
    #expect(Array(frame[decoded]) == payload)
    #expect(cursor == frame.count)
  }

  @Test
  internal func strict() {
    let payload = Array("}".utf8)
    #expect(throws: GDBPacketError.malformed) {
      var input = payload
      let count = input.count
      var span = input.mutableSpan
      _ = try GDBPacketFraming.decode(0 ..< count, input: &span,
                                      encoding: .binary)
    }
  }

  @Test
  internal func checksum() throws {
    var cursor = 0
    var frame = Array("$g#00".utf8)
    #expect(throws: GDBPacketError.checksum) {
      var input = frame.mutableSpan
      _ = try GDBPacketFraming.extract(&input, cursor: &cursor)
    }
    #expect(cursor == frame.count)

    cursor = 0
    let range = try extract(&frame, cursor: &cursor, checksum: false)
    #expect(range == 1 ..< 2)
    #expect(cursor == frame.count)
  }

  @Test
  internal func capacity() {
    var response = Array<UInt8>()
    typealias Failure = GDBHandlerError
    #expect(throws: GDBHandlerError.capacity) {
      try response.append(addingCapacity: 2) { output throws(Failure) in
        try output.append("long")
      }
    }
    #expect(response.isEmpty)
  }

  @Test
  internal func growth() throws {
    let packet = Array("jGetLoadedDynamicLibrariesInfos:{}".utf8)
    let storage = try TestConnection(frame(packet.span, encoding: .binary))
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: GrowthRouter.self, compatibility: .lldb,
                   capacity: 64)
    try remote.step()

    let payload = Array(repeating: UInt8(ascii: "a"), count: 256)
    var expected: Array<UInt8> = [UInt8(ascii: "+")]
    expected.append(contentsOf: frame(payload.span, encoding: .binary))
    #expect(storage.output == expected)
  }

  @Test
  internal func overflow() throws {
    let packet = Array("qUnknown".utf8)
    let storage = try TestConnection(frame(packet.span))
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: OverflowRouter.self, compatibility: .gdb,
                   capacity: 16)
    try remote.step()

    let payload = Array("E01".utf8)
    var expected: Array<UInt8> = [UInt8(ascii: "+")]
    expected.append(contentsOf: frame(payload.span))
    #expect(storage.output == expected)
  }

  @Test
  internal func inbound() throws {
    let input = Array("$aaaaaaaaaaaa".utf8)
    let storage = try TestConnection(input)
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: DefaultRouter.self, compatibility: .gdb, capacity: 4)
    do {
      try remote.step()
      Issue.record("oversized inbound packet was accepted")
    } catch .capacity {
    } catch {
      Issue.record("unexpected inbound capacity error: \(error)")
    }
  }

  @Test
  internal func reader() throws {
    let packet = Array("qSupported:1a;tail".utf8)
    var reader = GDBPacketReader(packet.span)
    let command = reader.consume("qSupported")
    let colon = reader.consume(0x3a)
    let value = try reader.hex()
    let separator = reader.consume(0x3b)
    let remaining = reader.remaining()
    let count = remaining.count
    let first = remaining[0]
    #expect(command)
    #expect(colon)
    #expect(value == 0x1a)
    #expect(separator)
    #expect(count == 4)
    #expect(first == 0x74)
  }

  @Test
  internal func matching() {
    let exact = GDBPacketPattern("qState")
    let prefix = GDBPacketPattern("qState", exact: false)
    let packet = Array("qState".utf8)
    let extended = Array("qState:more".utf8)
    let matched = exact.matches(packet.span)
    let rejected = exact.matches(extended.span)
    let accepted = prefix.matches(packet.span)
    let suffixed = prefix.matches(extended.span)
    #expect(matched)
    #expect(rejected == false)
    #expect(accepted)
    #expect(suffixed)
  }

  @Test
  internal func classification() {
    let cases: Array<(String, GDBPacketLeaf, Int)> = [
      ("!", .extended, 1),
      ("?", .stop, 1),
      ("B1234,S", .breakpoint, 1),
      ("I6869", .input, 1),
      ("C0b;1234", .C, 1),
      ("QEnvironmentHexEncoded:413d42", .environment, 23),
      ("QLaunchArch:arm64", .QLaunchArch, 12),
      ("QSetMaxPacketSize:1000", .QSetMaxPacketSize, 18),
      ("QSetSTDERR:2", .stderr, 11),
      ("qFileLoadAddress:/tmp/a", .qFileLoadAddress, 17),
      ("qEcho:hello", .qEcho, 6),
      ("qGDBServerVersion", .version, 17),
      ("qGetPid", .qGetPid, 7),
      ("qGetTLSAddr:1,2,3", .tls, 12),
      ("jGetDyldProcessState", .loader, 20),
      ("jMultiBreakpoint:{}", .jMultiBreakpoint, 17),
      ("qMemoryRegionInfo", .qMemoryRegionInfo, 17),
      ("qMemoryRegionInfo:1000", .qMemoryRegionInfo, 18),
      ("qMemoryRegionInfoSupported", .qMemoryRegionInfoSupported, 26),
      ("qOffsets", .qOffsets, 8),
      ("qPlatform_shell:echo", .qPlatform_shell, 16),
      ("qProcessInfo", .qProcessInfo, 12),
      ("qProcessInfoPID:2a", .process, 16),
      ("qfProcessInfo:name:74657374;", .qfProcessInfo, 13),
      ("qQueryGDBServer", .qQueryGDBServer, 15),
      ("qRcmd,65786974", .qRcmd, 6),
      ("qShlibInfoAddr", .qShlibInfoAddr, 14),
      ("qStepPacketSupported", .qStepPacketSupported, 20),
      ("qSpeedTest:response_size:4;", .qSpeedTest, 11),
      ("qSupported:multiprocess+", .supported, 10),
      ("qSupportsDetachAndStayStopped:", .qSupportsDetachAndStayStopped, 30),
      ("qSyncThreadStateSupported", .qSyncThreadStateSupported, 25),
      ("qThreadStopInfo2", .qThreadStopInfo, 15),
      ("qVAttachOrWaitSupported", .qVAttachOrWaitSupported, 23),
      ("qWatchpointSupportInfo", .qWatchpointSupportInfo, 22),
      ("qWatchpointSupportInfo:", .qWatchpointSupportInfo, 23),
      ("qXfer:features:read:target.xml:0,fff", .transfer(.features), 15),
      ("qXfer:exec-file:read::0,fff", .transfer(.executable), 16),
      ("qXfer:auxv:read::0,fff", .transfer(.auxiliary), 11),
      ("vAttachOrWait;name", .vAttachOrWait, 14),
      ("vCont?", .vCont, 5),
    ]
    for (packet, leaf, payload) in cases {
      let bytes = Array(packet.utf8)
      let match = GDBPacketClassifier.classify(bytes.span)
      #expect(match.leaf == leaf)
      #expect(match.payload == payload)
    }
    let unsupported = Array("qProcessInfoSuffix".utf8)
    let match = GDBPacketClassifier.classify(unsupported.span)
    #expect(match.leaf == .unsupported)

    let remote = Array("qGDBServerVersion".utf8)
    let session = Array("QEnvironmentHexEncoded:413d42".utf8)
    let mode = Array("vCont?".utf8)
    let server = GDBPacketClassifier.classify(remote.span)
    let settings = GDBPacketClassifier.classify(session.span)
    let execution = GDBPacketClassifier.classify(mode.span)
    #expect(server.route == .remote)
    #expect(server.leaf == .version)
    #expect(settings.route == .session)
    #expect(settings.leaf == .environment)
    #expect(execution.route == .mode)
    #expect(execution.leaf == .vCont)

    let write = Array("X1000,4:data".utf8)
    let read = Array("x1000,4".utf8)
    let transfer = Array("qXfer:auxv:read::0,fff".utf8)
    let file = Array("vFile:pread:1,4,0".utf8)
    let modules = Array("jModulesInfo:[]".utf8)
    let batch = Array("jMultiBreakpoint:{}".utf8)
    let signals = Array("jSignalsInfo".utf8)
    let threads = Array("jThreadsInfo".utf8)
    let loader = Array("jGetDyldProcessState".utf8)
    let writing = GDBPacketClassifier.classify(write.span)
    let reading = GDBPacketClassifier.classify(read.span)
    let transferring = GDBPacketClassifier.classify(transfer.span)
    let filing = GDBPacketClassifier.classify(file.span)
    let querying = GDBPacketClassifier.classify(modules.span)
    let batching = GDBPacketClassifier.classify(batch.span)
    let catalog = GDBPacketClassifier.classify(signals.span)
    let listing = GDBPacketClassifier.classify(threads.span)
    let loading = GDBPacketClassifier.classify(loader.span)
    #expect(writing.request == .binary)
    #expect(writing.response == .text)
    #expect(reading.request == .text)
    #expect(reading.response == .binary)
    #expect(transferring.request == .text)
    #expect(transferring.response == .binary)
    #expect(filing.request == .binary)
    #expect(filing.response == .binary)
    #expect(querying.request == .binary)
    #expect(querying.response == .binary)
    #expect(batching.request == .binary)
    #expect(batching.response == .binary)
    #expect(catalog.request == .text)
    #expect(catalog.response == .text)
    #expect(listing.request == .text)
    #expect(listing.response == .binary)
    #expect(loading.request == .text)
    #expect(loading.response == .binary)
  }

  @Test
  internal func legacy() throws {
    var input = Array<UInt8>()
    for value in ["!", "b9600", "d", "qRcmd,65786974"] {
      let packet = Array(value.utf8)
      input.append(contentsOf: frame(packet.span))
    }
    let storage = try TestConnection(input)
    var remote =
        GDBRemote(channel: storage.connect(), session: DebugSession(),
                  compatibility: .gdb)
    for _ in 0 ..< 4 {
      try remote.step()
    }
    var expected = Array<UInt8>()
    let okay = Array("OK".utf8)
    for _ in 0 ..< 4 {
      expected.append(0x2b)
      expected.append(contentsOf: frame(okay.span))
    }
    #expect(storage.output == expected)
    let complete = remote.complete
    #expect(complete)
  }

  @Test
  internal func echo() throws {
    var input = Array<UInt8>()
    for value in ["qEcho:hello", "qSpeedTest:response_size:4;",
                  "qSupportsDetachAndStayStopped:"] {
      let packet = Array(value.utf8)
      input.append(contentsOf: frame(packet.span))
    }
    let storage = try TestConnection(input)
    var remote =
        GDBRemote(channel: storage.connect(), session: DebugSession(),
                  compatibility: .lldb)
    try remote.step()
    try remote.step()
    try remote.step()

    var expected = Array<UInt8>()
    for value in ["hello", "data:1234", "OK"] {
      expected.append(0x2b)
      let packet = Array(value.utf8)
      expected.append(contentsOf: frame(packet.span))
    }
    #expect(storage.output == expected)
  }

  @Test
  internal func selection() {
    let process = ProcessIdentifier(rawValue: 7)
    let thread = ThreadIdentifier(rawValue: 11)
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    let selection = GDBRemoteSelection(stopped: identifier)
    var state = GDBRemoteSessionState(compatibility: .gdb, selection: selection)
    state.selection.general = .thread(identifier)
    state.selection.resume = .all
    #expect(state.selection.general == .thread(identifier))
    #expect(state.selection.resume == .all)
    #expect(state.selection.stopped == identifier)
  }

  @Test
  internal func identity() throws {
    let process = ProcessIdentifier(rawValue: 7)
    // Keep the synthetic record disjoint from a live host thread. Otherwise a
    // coincidental identifier match can add host register values to the reply.
    let thread = ThreadIdentifier(rawValue: 0)
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    let stop = Debuggee.Stop(thread: identifier, reason: .breakpoint)
    let record = Debuggee.Thread(identifier: identifier, state: .stopped(stop))
    let debuggee =
        Debuggee(processes: [
          Debuggee.Process(identifier: process, state: .stopped,
                           threads: [record], current: thread),
        ])
    var input = Array<UInt8>()
    for value in ["qSupported:multiprocess+", "?", "qC"] {
      let packet = Array(value.utf8)
      input.append(contentsOf: frame(packet.span))
    }
    let storage = try TestConnection(input)
    var remote =
        GDBRemote(channel: storage.connect(),
                  session: DebugSession(debuggee: debuggee),
                  compatibility: .gdb)
    try remote.step()
    try remote.step()
    try remote.step()

    var supported =
        "PacketSize=\(kCapacity)\(kWatchpoints);QStartNoAckMode+;" +
        "multiprocess+;" +
        "qXfer:features:read+"
    if DebugCapabilities.current.contains(.executable) {
      supported += ";qXfer:exec-file:read+"
    }
    if DebugCapabilities.current.contains(.auxiliary) {
      supported += ";qXfer:auxv:read+"
    }
    if DebugCapabilities.current.contains(.libraries) {
      supported += ";qXfer:libraries:read+"
    }
    if DebugCapabilities.current.contains(.svr4) {
      supported += ";qXfer:libraries-svr4:read+"
    }
    supported += ";qXfer:threads:read+"
    if DebugCapabilities.current.contains(.signal) {
      supported += ";qXfer:siginfo:read+"
    }
    supported += ";QThreadSuffixSupported+;QListThreadsInStopReply+"
    if DebugCapabilities.current.contains(.passthrough) {
      supported += ";QPassSignals+"
    }
    if DebugCapabilities.current.contains(.randomization) {
      supported += ";QDisableRandomization+"
    }
    supported +=
        ";QEnvironmentReset+;QEnvironmentUnset+;vContSupported+;" +
        "swbreak+;hwbreak+;QNonStop+;jMultiBreakpoint+;binary-upload+;" +
        "exec-events+;qXfer:memory-map:read+"
    if DebugCapabilities.current.contains(.threads) {
      supported += ";QThreadEvents+"
    }
    if DebugCapabilities.current.contains(.syscalls) {
      supported += ";QCatchSyscalls+"
    }
    if DebugCapabilities.current.contains(.threads) {
      supported += ";QThreadOptions=2"
    }
    var expected = Array<UInt8>()
    for value in [
      supported,
      "T05thread:p7.0;",
      "QCp7.0",
    ] {
      let payload = Array(value.utf8)
      expected.append(0x2b)
      expected.append(contentsOf: frame(payload.span))
    }
    #expect(storage.output == expected)
  }

  @Test
  internal func selecting() throws {
    let process = ProcessIdentifier(rawValue: 7)
    let first = ThreadIdentifier(rawValue: 11)
    let identifier = ProcessThreadIdentifier(process: process, thread: first)
    let thread = Debuggee.Thread(identifier: identifier, state: .running)
    let child = Debuggee.Process(identifier: process, state: .stopped,
                                 threads: [thread], current: first)
    let debuggee = Debuggee(processes: [child])
    var input = Array<UInt8>()
    for value in ["Hgp7.b", "Hc-1", "Tp7.b", "Tp7.c"] {
      let packet = Array(value.utf8)
      input.append(contentsOf: frame(packet.span))
    }
    let storage = try TestConnection(input)
    var remote =
        GDBRemote(channel: storage.connect(),
                  session: DebugSession(debuggee: debuggee),
                  compatibility: .gdb)
    for _ in 0 ..< 4 {
      try remote.step()
    }

    var expected = Array<UInt8>()
    for value in ["OK", "OK", "OK", "E01"] {
      let payload = Array(value.utf8)
      expected.append(0x2b)
      expected.append(contentsOf: frame(payload.span))
    }
    #expect(storage.output == expected)
  }

  @Test
  internal func enumeration() throws {
    let process = ProcessIdentifier(rawValue: 7)
    var threads = Array<Debuggee.Thread>()
    for value in 1 ... 10 {
      let thread = ThreadIdentifier(rawValue: UInt64(value))
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      threads.append(Debuggee.Thread(identifier: identifier))
    }
    let debuggee =
        Debuggee(processes: [
          Debuggee.Process(identifier: process, state: .running,
                           threads: threads,
                           current: ThreadIdentifier(rawValue: 1)),
        ])
    var input = Array<UInt8>()
    for value in ["qfThreadInfo", "qsThreadInfo", "qsThreadInfo"] {
      let packet = Array(value.utf8)
      input.append(contentsOf: frame(packet.span))
    }
    let storage = try TestConnection(input)
    var remote =
        GDBRemote(channel: storage.connect(),
                  session: DebugSession(debuggee: debuggee),
                  compatibility: .gdb, capacity: 16)
    try remote.step()
    try remote.step()
    try remote.step()

    var expected = Array<UInt8>()
    for value in ["m1,2,3,4,5,6,7,8", "m9,a", "l"] {
      let payload = Array(value.utf8)
      expected.append(0x2b)
      expected.append(contentsOf: frame(payload.span))
    }
    #expect(storage.output == expected)
  }

  @Test
  internal func event() throws {
    let process = ProcessIdentifier(rawValue: 7)
    let identifier =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: .max))
    let stop = Debuggee.Stop(thread: identifier, reason: .interrupt)
    let storage = try TestConnection([])
    var remote = GDBRemote(channel: storage.connect(), session: DebugSession(),
                           compatibility: .gdb)
    try remote.handle(event: .stopped(stop))
    let payload = Array("T02thread:ffffffffffffffff;".utf8)
    #expect(storage.output == frame(payload.span))
    #expect(remote.core.state.selection.stopped == identifier)
  }

  @Test
  internal func termination() throws {
    let process = ProcessIdentifier(rawValue: 7)
    let legacy = try TestConnection(Array<UInt8>())
    var remote =
        GDBRemote(channel: legacy.connect(), session: DebugSession(),
                  compatibility: .lldb)
    remote.core.state.termination = .legacy(process)
    try remote.handle(event: .exited(process, .signalled(9)))

    let exited = Array(("X09;description:" +
        "5465726d696e617465642064756520746f207369676e616c2039;").utf8)
    #expect(legacy.output == frame(exited.span))
    if case .none = remote.core.state.termination {
    } else {
      Issue.record("legacy termination was not cleared")
    }

    let extended = try TestConnection(Array<UInt8>())
    var session =
        GDBRemote(channel: extended.connect(), session: DebugSession(),
                  compatibility: .lldb)
    session.core.state.termination = .extended(process)
    try session.handle(event: .exited(process, .signalled(9)))

    let okay = Array("OK".utf8)
    #expect(extended.output == frame(okay.span))
    if case .none = session.core.state.termination {
    } else {
      Issue.record("extended termination was not cleared")
    }

    let nonstop = try TestConnection(Array<UInt8>())
    var channel =
        GDBRemote(channel: nonstop.connect(), session: DebugSession(),
                  compatibility: .lldb)
    channel.core.state.nonstop = true
    channel.core.state.termination = .extended(process)
    try channel.handle(event: .exited(process, .signalled(9)))

    #expect(nonstop.output == frame(okay.span))
    if case .none = channel.core.state.termination {
    } else {
      Issue.record("non-stop termination was not cleared")
    }
  }

  @Test
  internal func notifications() throws {
    for compatibility in [CompatibilityMode.gdb, .lldb] {
      let storage = try TestConnection([])
      var remote = GDBRemote(channel: storage.connect(),
                             session: DebugSession(),
                             compatibility: compatibility)
      remote.core.state.nonstop = true
      let first = ProcessIdentifier(rawValue: 7)
      let second = ProcessIdentifier(rawValue: 8)
      try remote.handle(event: .exited(first, .exited(1)))
      try remote.handle(event: .exited(second, .exited(2)))
      var expected = frame(Array("Stop:W01".utf8).span)
      expected[0] = UInt8(ascii: "%")
      #expect(storage.output == expected)

      for reply in ["W02", "OK"] {
        try storage.send(frame(Array("vStopped".utf8).span))
        try remote.step()
        expected.append(UInt8(ascii: "+"))
        expected.append(contentsOf: frame(Array(reply.utf8).span))
        #expect(storage.output == expected)
      }
      let empty = remote.core.state.stops.first == nil
      #expect(empty)
    }
  }

  @Test
  internal func lifecycle() throws {
    for compatibility in [CompatibilityMode.gdb, .lldb] {
      let storage = try TestConnection([])
      var remote = GDBRemote(channel: storage.connect(),
                             session: DebugSession(),
                             compatibility: compatibility)
      remote.core.state.nonstop = true
      remote.core.state.events = true
      let thread =
          ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 7),
                                  thread: ThreadIdentifier(rawValue: 8))
      try remote.handle(event: .started(thread))
      let creation = String(decoding: storage.output, as: UTF8.self)
      #expect(creation.hasPrefix("%Stop:T05thread:8;"))
      let reason = compatibility == .gdb ? "create:;" : "reason:create;"
      #expect(creation.contains(reason))
      let state = remote.session.debuggee.state(thread)
      if case .stopped(let stop) = state {
        #expect(stop.reason == .create)
      } else {
        Issue.record("reported thread creation was not recorded as a stop")
      }
      let count = storage.output.count
      try remote.handle(event: .terminated(thread, 3))
      #expect(storage.output.count == count)
      try storage.send(frame(Array("vStopped".utf8).span))
      try remote.step()
      let exit =
          String(decoding: storage.output.dropFirst(count), as: UTF8.self)
      #expect(exit.hasPrefix("+$w03;8#"))
    }
  }

  @Test
  internal func snapshot() throws {
    let process = ProcessIdentifier(rawValue: 7)
    let running =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 8))
    let stopped =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 9))
    let stop = Debuggee.Stop(thread: stopped, reason: .interrupt)
    let debuggee = Debuggee(processes: [
      Debuggee.Process(identifier: process, state: .stopped, threads: [
        Debuggee.Thread(identifier: running, state: .running),
        Debuggee.Thread(identifier: stopped, state: .stopped(stop)),
      ]),
    ])
    let storage = try TestConnection([])
    var remote = GDBRemote(channel: storage.connect(),
                           session: DebugSession(debuggee: debuggee),
                           compatibility: .gdb)
    remote.core.state.nonstop = true
    try remote.handle(event: .exited(ProcessIdentifier(rawValue: 10),
                                     .exited(4)))
    storage.output.removeAll()
    for query in ["?", "vStopped", "vStopped"] {
      try storage.send(frame(Array(query.utf8).span))
      try remote.step()
    }
    let replies = String(decoding: storage.output, as: UTF8.self)
    #expect(replies.hasPrefix("+$W04#"))
    #expect(replies.contains("thread:9;"))
    #expect(replies.contains("thread:8;") == false)
    #expect(replies.hasSuffix(String(decoding: frame(Array("OK".utf8).span),
                                     as: UTF8.self)))
  }

  @Test
  internal func queue() throws {
    var stops = GDBRemoteStops()
    for value in 0 ..< 64 {
      let reply = Array("W\(value)".utf8)
      stops.record(reply.span)
    }
    for value in 0 ..< 32 {
      #expect(stops.first == Array("W\(value)".utf8))
      _ = stops.next()
    }
    for value in 64 ..< 96 {
      let reply = Array("W\(value)".utf8)
      stops.record(reply.span)
    }
    for value in 32 ..< 96 {
      #expect(stops.first == Array("W\(value)".utf8))
      _ = stops.next()
    }
    #expect(stops.first == nil)
    #expect(stops.next() == nil)
  }

  @Test
  internal func running() throws {
    let process = ProcessIdentifier(rawValue: 7)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 8))
    let debuggee = Debuggee(processes: [
      Debuggee.Process(identifier: process, state: .running, threads: [
        Debuggee.Thread(identifier: thread, state: .running),
      ]),
    ])
    let storage = try TestConnection(frame(Array("?".utf8).span))
    var remote = GDBRemote(channel: storage.connect(),
                           session: DebugSession(debuggee: debuggee),
                           compatibility: .gdb)
    remote.core.state.nonstop = true
    try remote.step()
    let expected = [UInt8(ascii: "+")] + frame(Array("OK".utf8).span)
    #expect(storage.output == expected)
  }

  @Test(arguments: [CompatibilityMode.gdb, .lldb])
  internal func passthrough(_ compatibility: CompatibilityMode) throws {
    guard NativeDebugControl.capabilities.contains(.passthrough) else {
      return
    }
#if os(Android) || os(Linux)
    let native: CInt = 10
    let encoded = compatibility == .gdb ? "1e" : "a"
#else
    let native: CInt = 29
    let encoded = compatibility == .gdb ? "8e" : "1d"
#endif
    let payload = Array("QPassSignals:\(encoded)".utf8)
    let storage = try TestConnection(frame(payload.span))
    var remote = GDBRemote(channel: storage.connect(), session: DebugSession(),
                           compatibility: compatibility)
    try remote.step()
    #expect(remote.session.signals.contains(native))
    #expect(remote.session.signals.contains(9) == false)
    let expected = [UInt8(ascii: "+")] + frame(Array("OK".utf8).span)
    #expect(storage.output == expected)
  }

  @Test(arguments: [CompatibilityMode.gdb, .lldb])
  internal func signalled(_ compatibility: CompatibilityMode) throws {
    let storage = try TestConnection([])
    var remote = GDBRemote(channel: storage.connect(), session: DebugSession(),
                           compatibility: compatibility)
    let process = ProcessIdentifier(rawValue: 7)
    try remote.handle(event: .exited(process, .signalled(29)))
#if os(Android) || os(Linux)
    let expected = compatibility == .gdb ? "X17" : "X1d"
#else
    let expected = compatibility == .gdb ? "X8e" : "X1d"
#endif
    let description = if compatibility == .lldb {
      ";description:" +
          "5465726d696e617465642064756520746f207369676e616c203239;"
    } else {
      ""
    }
    #expect(storage.output == frame(Array((expected + description).utf8).span))
  }

  @Test
  internal func eventafterpacket() throws {
    let process = ProcessIdentifier(rawValue: 7)
    let packet = Array("qUnsupported".utf8)
    let storage = try TestConnection(frame(packet.span))
    var remote = GDBRemote(channel: storage.connect(), session: DebugSession(),
                           compatibility: .gdb)
    try remote.step()
    try remote.handle(event: .exited(process, .exited(0)))
    var expected: Array<UInt8> = [0x2b]
    let empty = Array<UInt8>()
    expected.append(contentsOf: frame(empty.span))
    let payload = Array("W00".utf8)
    expected.append(contentsOf: frame(payload.span))
    #expect(storage.output == expected)
  }

  @Test
  internal func platform() throws {
    var input = Array<UInt8>()
    for query in ["qSupported", "jModulesInfo:[]", "?"] {
      let packet = Array(query.utf8)
      input.append(contentsOf: frame(packet.span))
    }
    let storage = try TestConnection(input)
    var remote = PlatformRemote(channel: storage.connect(),
                                session: PlatformSession(),
                                compatibility: .lldb)
    defer {
      remote.close()
    }
    for _ in 0 ..< 3 {
      try remote.step()
    }
    let capacity = String(Configuration.PlatformPacketCapacity, radix: 16)
    let supported = "PacketSize=\(capacity)\(kWatchpoints);QStartNoAckMode+"
    var expected = Array<UInt8>()
    for reply in [supported, "[]", ""] {
      expected.append(0x2b)
      let payload = Array(reply.utf8)
      expected.append(contentsOf: frame(payload.span))
    }
    #expect(storage.output == expected)
  }

  @Test
  internal func transfer() throws {
    let query = Array("qXfer:auxv:read::0,2:".utf8)
    let storage = try TestConnection(frame(query.span))
    var remote =
        TestRemote(channel: storage.connect(), session: TransferSession(),
                   router: TransferRouter.self, compatibility: .gdb)
    try remote.step()

    var expected: Array<UInt8> = [0x2b]
    let payload = Array("mte".utf8)
    expected.append(contentsOf: frame(payload.span))
    #expect(storage.output == expected)
  }

  @Test
  internal func errors() throws {
    let query = Array("qFailure".utf8)
    let storage = try TestConnection(frame(query.span))
    var remote =
        TestRemote(channel: storage.connect(), session: TestSession(),
                   router: FailureRouter.self, compatibility: .gdb)
    try remote.step()

    let payload = Array("E0d".utf8)
    var expected: Array<UInt8> = [0x2b]
    expected.append(contentsOf: frame(payload.span))
    #expect(storage.output == expected)

    let malformed = try TestConnection(frame(query.span))
    var invalid =
        TestRemote(channel: malformed.connect(), session: TestSession(),
                   router: MalformedRouter.self, compatibility: .gdb)
    try invalid.step()

    let error = Array("E03".utf8)
    var rejected: Array<UInt8> = [0x2b]
    rejected.append(contentsOf: frame(error.span))
    #expect(malformed.output == rejected)
  }

  @Test
  internal func policy() {
    let state =
        GDBRemoteSessionState(compatibility: .lldb,
                              features: [.features, .multiprocess])
    let transfer = GDBPacketClassifier.classify(Array("qXfer:".utf8).span)
    let module = GDBPacketClassifier.classify(Array("qModuleInfo:".utf8).span)
    var allowed = GDBPacketClassifier.allows(transfer, state)
    #expect(allowed)
    allowed = GDBPacketClassifier.allows(module, state)
    #expect(allowed)
    let gdb = GDBRemoteSessionState(compatibility: .gdb)
    allowed = GDBPacketClassifier.allows(module, gdb)
    #expect(allowed == false)

    let aslr = GDBPacketClassifier.classify(Array("QDisableASLR:".utf8).span)
    let bytes = Array("QDisableRandomization:".utf8)
    let randomization = GDBPacketClassifier.classify(bytes.span)
    allowed = GDBPacketClassifier.allows(aslr, state)
    #expect(allowed)
    allowed = GDBPacketClassifier.allows(randomization, state)
    #expect(allowed == false)
  }

  @Test
  internal func negotiation() throws {
    var input = Array<UInt8>()
    for value in [
      "qSupported:multiprocess+;PacketSize=80",
      "qState",
    ] {
      let message = Array(value.utf8)
      input.append(contentsOf: frame(message.span))
    }
    let storage = try TestConnection(input)
    var remote =
        TestRemote(channel: storage.connect(), session: TestSession(),
                   router: StateRouter.self, compatibility: .lldb)
    try remote.step()
    try remote.step()

    let supported =
        "PacketSize=\(kCapacity)\(kWatchpoints);QStartNoAckMode+;" +
        "multiprocess+"
    let payload = Array(supported.utf8)
    var expected: Array<UInt8> = [0x2b]
    expected.append(contentsOf: frame(payload.span))
    expected.append(0x2b)
    let state = Array("80;negotiated".utf8)
    expected.append(contentsOf: frame(state.span))
    #expect(storage.output == expected)
  }

  @Test
  internal func querying() throws {
    var input = Array<UInt8>()
    for value in [
      "qSupported:multiprocess?;PacketSize=40",
      "qState",
    ] {
      let message = Array(value.utf8)
      input.append(contentsOf: frame(message.span))
    }
    let storage = try TestConnection(input)
    var remote =
        TestRemote(channel: storage.connect(), session: TestSession(),
                   router: StateOnlyRouter.self, compatibility: .gdb)
    try remote.step()
    try remote.step()

    let response = "PacketSize=\(kCapacity)\(kWatchpoints)"
    let advertised = if response.utf8.count <= 0x40 {
      Array(response.utf8)
    } else {
      Array("PacketSize=\(kCapacity)".utf8)
    }
    let state = Array("40".utf8)
    var expected = Array<UInt8>()
    for payload in [advertised, state] {
      expected.append(0x2b)
      expected.append(contentsOf: frame(payload.span))
    }
    #expect(storage.output == expected)
  }

  @Test
  internal func noack() throws {
    var input = Array<UInt8>()
    for value in [
      "qSupported",
      "QStartNoAckMode",
      "qSupported",
    ] {
      let message = Array(value.utf8)
      input.append(contentsOf: frame(message.span))
    }
    let storage = try TestConnection(input)
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: DefaultRouter.self, compatibility: .gdb)
    try remote.step()
    try remote.step()
    try remote.step()

    var expected = Array<UInt8>()
    let supported =
        Array("PacketSize=\(kCapacity)\(kWatchpoints);QStartNoAckMode+".utf8)
    expected.append(0x2b)
    expected.append(contentsOf: frame(supported.span))
    expected.append(0x2b)
    let ok = Array("OK".utf8)
    expected.append(contentsOf: frame(ok.span))
    expected.append(contentsOf: frame(supported.span))
    #expect(storage.output == expected)
  }

  @Test
  internal func handshake() throws {
    let query = Array("QStartNoAckMode".utf8)
    let storage = try TestConnection(frame(query.span))
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: DefaultRouter.self, compatibility: .gdb)
    try remote.step()

    let ok = Array("OK".utf8)
    var expected: Array<UInt8> = [0x2b]
    expected.append(contentsOf: frame(ok.span))
    #expect(storage.output == expected)
  }

  @Test
  internal func replacement() throws {
    var input = Array<UInt8>()
    for value in [
      "qSupported:multiprocess+",
      "qSupported:multiprocess-",
      "qState",
    ] {
      let message = Array(value.utf8)
      input.append(contentsOf: frame(message.span))
    }
    let storage = try TestConnection(input)
    var remote =
        TestRemote(channel: storage.connect(), session: TestSession(),
                   router: StateOnlyRouter.self, compatibility: .gdb)
    try remote.step()
    try remote.step()
    try remote.step()

    let advertised =
        Array("PacketSize=\(kCapacity)\(kWatchpoints);multiprocess+".utf8)
    let replaced = Array("PacketSize=\(kCapacity)\(kWatchpoints)".utf8)
    let state = Array(kCapacity.utf8)
    var expected = Array<UInt8>()
    for payload in [advertised, replaced, state] {
      expected.append(0x2b)
      expected.append(contentsOf: frame(payload.span))
    }
    #expect(storage.output == expected)
  }

  @Test
  internal func target() throws {
    let query = Array("qTarget".utf8)
    let storage = try TestConnection(frame(query.span))
    var remote =
        TestRemote(channel: storage.connect(), session: TestSession(),
                   router: StubRouter.self, compatibility: .gdb)
    try remote.step()

    let payload = Array("1".utf8)
    var expected: Array<UInt8> = [0x2b]
    expected.append(contentsOf: frame(payload.span))
    #expect(storage.output == expected)
  }

  @Test
  internal func recovery() throws {
    var input = Array("$g#00".utf8)
    let query = Array("qSupported".utf8)
    input.append(contentsOf: frame(query.span))
    let storage = try TestConnection(input)
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: DefaultRouter.self, compatibility: .gdb)
    try remote.step()
    #expect(storage.output == [0x2d])

    try remote.step()
    let payload =
        Array("PacketSize=\(kCapacity)\(kWatchpoints);QStartNoAckMode+".utf8)
    var expected: Array<UInt8> = [0x2d, 0x2b]
    expected.append(contentsOf: frame(payload.span))
    #expect(storage.output == expected)
  }

  @Test
  internal func retransmission() throws {
    var input = Array<UInt8>()
    let query = Array("qSupported".utf8)
    input.append(contentsOf: frame(query.span))
    input.append(0x2d)
    let storage = try TestConnection(input)
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: DefaultRouter.self, compatibility: .gdb)
    try remote.step()
    let first = storage.output
    try remote.step()

    let frame = Array(first.dropFirst())
    var expected = first
    expected.append(contentsOf: frame)
    #expect(storage.output == expected)
  }

  @Test
  internal func interrupt() throws {
    let storage = try TestConnection([0x03])
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: DefaultRouter.self, compatibility: .gdb)
    try remote.step()
    #expect(storage.output.isEmpty)
  }

  @Test
  internal func waitcancel() throws {
    let request =
        Array("vAttachWait;6473782d6e6f2d737563682d70726f63657373".utf8)
    var input = frame(request.span)
    input.append(0x03)
    let storage = try TestConnection(input)
    var remote =
        GDBRemote(channel: storage.connect(), session: DebugSession(),
                  compatibility: .lldb)
    try remote.step()

    let error = Array("E04".utf8)
    var expected: Array<UInt8> = [0x2b]
    expected.append(contentsOf: frame(error.span))
    #expect(storage.output == expected)
  }

  @Test
  internal func waitdisconnect() throws {
    let request =
        Array("vAttachWait;6473782d6e6f2d737563682d70726f63657373".utf8)
    let storage = try TestConnection(frame(request.span))
    storage.finish()
    var remote =
        GDBRemote(channel: storage.connect(), session: DebugSession(),
                  compatibility: .lldb)
    do {
      try remote.step()
      Issue.record("deferred wait accepted a closed channel")
    } catch .closed {
    } catch {
      Issue.record("unexpected deferred wait failure: \(error)")
    }
    #expect(storage.output == [0x2b])
  }

  @Test
  internal func stubs() throws {
    var input = Array<UInt8>()
    for value in ["m0,1", "QAgent:1", "qUnknown"] {
      let packet = Array(value.utf8)
      input.append(contentsOf: frame(packet.span))
    }
    let storage = try TestConnection(input)
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: DefaultRouter.self, compatibility: .gdb)
    try remote.step()
    try remote.step()
    try remote.step()

    let empty = Array<UInt8>()
    var expected = Array<UInt8>()
    for _ in 0 ..< 3 {
      expected.append(0x2b)
      expected.append(contentsOf: frame(empty.span))
    }
    #expect(storage.output == expected)
  }

  @Test
  internal func unsupported() throws {
    let query = Array("qUnknown".utf8)
    let storage = try TestConnection(frame(query.span))
    var remote =
        TestRemote(channel: storage.connect(), session: DebugSession(),
                   router: DefaultRouter.self, compatibility: .gdb)
    try remote.step()

    var expected: Array<UInt8> = [0x2b]
    let empty = Array<UInt8>()
    expected.append(contentsOf: frame(empty.span))
    #expect(storage.output == expected)
  }
}

private func frame(_ message: borrowing Span<UInt8>,
                   encoding: GDBPacketEncoding = .text) -> Array<UInt8> {
  var frame = Array<UInt8>()
  let capacity = GDBPacketFraming.capacity(message.count)
  frame.append(addingCapacity: capacity) { output in
    GDBPacketFraming.frame(message, encoding: encoding, output: &output)
  }
  return frame
}
