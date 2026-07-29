// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

private let kCapacity = String(Configuration.PacketCapacity, radix: 16)
private typealias ProcessOutput = OutputSpan<ProcessIdentifier>

private enum QueryModules {
  internal static func info(_ path: String) throws(Debuggee.Error)
      -> Debuggee.Module {
    if path == "missing" {
      throw .process
    }
    let identifier = path == "anonymous" ? nil : "0123"
    let identity: Debuggee.Module.Identity? = if let identifier {
      .unique(identifier)
    } else {
      nil
    }
    return Debuggee.Module(path: path, identity: identity,
                           base: Debuggee.Address(rawValue: 0), size: 0x20)
  }
}

private final class QueryStorage: @unchecked Sendable {
  fileprivate var process: ProcessIdentifier?
  fileprivate var thread: ProcessThreadIdentifier?
}

private struct QueryTransfer: Sendable {
  fileprivate let storage: QueryStorage

  internal func read(_ object: GDBTransferObject, process: ProcessIdentifier?,
                     thread: ProcessThreadIdentifier?, offset: UInt64,
                     limit: Int, into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> ReadStatus {
    storage.process = process
    storage.thread = thread
    output.append(0xaa)
    return .last
  }
}

private struct QueryPlatform: Sendable {
  fileprivate mutating func list(_ cursor: inout Int?,
                                 into output: inout ProcessOutput)
      throws(Debuggee.Error) {
  }

  fileprivate func info(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Debuggee.Process.Info {
    Debuggee.Process.Info(process: process,
                          parent: ProcessIdentifier(rawValue: 10),
                          name: "inferior",
                          arguments: ["/tmp/inferior", "10", "qu'o'tes\"",
                                  "מזל טוב"], architecture: "x86_64")
  }

  fileprivate mutating func next(_ cursor: inout Int?) throws(Debuggee.Error)
      -> ProcessIdentifier? {
    throw .unsupported
  }
}

private struct QueryImages: Sendable {
  fileprivate var images: Array<Debuggee.Image>
  fileprivate var failure: Debuggee.Error?

  fileprivate init(images: Array<Debuggee.Image> = [
    Debuggee.Image(path: "", base: Debuggee.Address(rawValue: 0x1234),
                   main: true),
    Debuggee.Image(path: "library", base: Debuggee.Address(rawValue: 0x5678)),
  ], failure: Debuggee.Error? = nil) {
    self.images = images
    self.failure = failure
  }

  fileprivate mutating func list(_ process: ProcessIdentifier,
                                 cursor: inout Int?,
                                 into output: inout OutputSpan<Debuggee.Image>)
      throws(Debuggee.Error) {
    if let failure {
      throw failure
    }
    let index = cursor ?? 0
    guard index < images.count else {
      return
    }
    output.append(images[index])
    cursor = index + 1
  }
}

private struct QueryProcessSession: Sendable {
  fileprivate var images: QueryImages
  fileprivate var platform = QueryPlatform()
  fileprivate var debuggee =
      Debuggee(processes: [
        Debuggee.Process(identifier: ProcessIdentifier(rawValue: 0x1a)),
      ])

  fileprivate init(images: QueryImages = QueryImages()) {
    self.images = images
  }
}

private enum QueryImagePacket: GDBPacketHandler {
  internal typealias Context = QueryProcessSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qFileLoadAddress:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout QueryProcessSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    var images = Array<Debuggee.Image>()
    images.reserveCapacity(1)
    var cursor: Int?
    while true {
      images.removeAll(keepingCapacity: true)
      do throws(Debuggee.Error) {
        try images.append(addingCapacity: 1) { output throws(Debuggee.Error) in
          try session.images.list(process, cursor: &cursor, into: &output)
        }
      } catch {
        throw .debuggee(error)
      }
      guard !images.isEmpty else {
        break
      }
      let address =
          try GDBFileLoadAddressPacket.address(payload,
                                               debuggee: session.debuggee,
                                               images: images.span,
                                               state: state)
      if let address {
        try writer.hex(address.rawValue)
        return .reply
      }
    }
    throw .code(GDBErrorCode.failure)
  }
}

private enum QueryCurrentProcessInfoPacket: GDBPacketHandler {
  internal typealias Context = QueryProcessSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qProcessInfo")
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout QueryProcessSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard !session.debuggee.processes.isEmpty else {
      throw .code(GDBErrorCode.process)
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    let info: Debuggee.Process.Info
    do {
      info = try session.platform.info(process)
    } catch {
      throw .debuggee(error)
    }
    session.debuggee.update(info)
    try writer.emit(info, hex: true)
    return .reply
  }
}

private enum QueryProcessInfoPacket: GDBPacketHandler {
  internal typealias Context = QueryProcessSession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qProcessInfoPID:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout QueryProcessSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    var reader = GDBPacketReader(payload.extracting(0...))
    let process = try ProcessIdentifier(rawValue: reader.decimal())
    guard reader.empty else {
      throw .malformed
    }
    let info: Debuggee.Process.Info
    do {
      info = try session.platform.info(process)
    } catch {
      throw .debuggee(error)
    }
    try writer.emit(info, hex: false)
    return .reply
  }
}

private struct QuerySession: Sendable {
  internal var queries: QueryTransfer
  internal var debuggee: Debuggee

  fileprivate init(_ storage: QueryStorage = QueryStorage()) {
    let process = ProcessIdentifier(rawValue: 1)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 2))
    queries = QueryTransfer(storage: storage)
    debuggee =
        Debuggee(processes: [
          Debuggee.Process(identifier: process, state: .stopped,
                           threads: [Debuggee.Thread(identifier: thread)],
                           current: thread.thread),
        ])
  }
}

private enum QueryModulePacket: GDBPacketHandler {
  internal typealias Context = QuerySession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qModuleInfo:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session _: inout QuerySession,
                              state _: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let request = try GDBModuleRequest(payload)
    let module = try translate(QueryModules.info(request.path))
    try writer.emit(module, request: request)
    return .reply
  }
}

private enum QueryModulesPacket: GDBPacketHandler {
  internal typealias Context = QuerySession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("jModulesInfo:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    []
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session _: inout QuerySession,
                              state _: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    var reader = try GDBModulesReader(payload.extracting(0...))
    try writer.append(UInt8(ascii: "["))
    var comma = false
    while let request = try reader.next() {
      let module: Debuggee.Module
      do {
        module = try QueryModules.info(request.path)
      } catch {
        continue
      }
      guard let identity = module.identity else {
        continue
      }
      if comma {
        try writer.append(UInt8(ascii: ","))
      }
      try writer.emit(json: module, request: request,
                      identifier: identity.value)
      comma = true
    }
    try writer.append(UInt8(ascii: "]"))
    return .reply
  }
}

private enum QueryTransferPacket: GDBPacketHandler {
  internal typealias Context = QuerySession

  internal static var packet: GDBPacketPattern {
    GDBPacketPattern("qXfer:", exact: false)
  }

  internal static var features: GDBRemoteFeatures {
    [.auxiliary, .libraries]
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout QuerySession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    let read: GDBTestTransferReader = { kind, pid, tid, base, size, output in
      try session.queries.read(kind, process: pid, thread: tid, offset: base,
                               limit: size, into: &output)
    }
    return try GDBTestTransfer.handle(payload, debuggee: session.debuggee,
                                      state: state, writer: &writer, read: read)
  }
}

private enum QueryRouter {
  internal typealias Context = QuerySession

  internal static var features: GDBRemoteFeatures {
    GDBRemoteFeatures.noack.union(QueryTransferPacket.features)
  }

  internal static func dispatch(_ leaf: GDBPacketLeaf,
                                payload packet: borrowing Span<UInt8>,
                                session: inout Context,
                                state: inout GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    switch leaf {
    case .module:
      return try GDBPacketDispatch.handle(QueryModulePacket.self,
                                          payload: packet, session: &session,
                                          state: &state, writer: &writer)
    case .modules:
      return try GDBPacketDispatch.handle(QueryModulesPacket.self,
                                          payload: packet, session: &session,
                                          state: &state, writer: &writer)
    case .transfer(.auxiliary):
      return try GDBPacketDispatch.handle(QueryTransferPacket.self,
                                          payload: packet, session: &session,
                                          state: &state, writer: &writer)
    case .QStartNoAckMode:
      return try GDBNoAckPacket.handle(state: &state, writer: &writer)
    case .supported:
      try GDBSupportedPacket.handle(packet, state: &state, writer: &writer)
      return .reply
    default:
      throw .unsupported
    }
  }
}

@Suite
internal struct GDBQueryPacketTests {
  private typealias Failure = GDBHandlerError

  @Test
  internal func module() throws {
    var session = QuerySession()
    let path = encode("/tmp/a.out")
    let triple = encode("x86_64-unknown-linux")
    let packet = "qModuleInfo:\(path);\(triple)"
    let response =
        try response(QueryModulePacket.self, packet: packet, session: &session)
    let expected =
        "uuid:30313233;triple:\(triple);file_path:\(path);" +
        "file_offset:0;file_size:20;"
    #expect(response == Array(expected.utf8))
    let request =
        GDBModuleRequest(path: "/tmp/a.out", triple: "x86_64-unknown-linux")
    let matching =
        Debuggee.Module(path: "/tmp/a.out", architecture: "x86_64",
                        base: Debuggee.Address(rawValue: 0), size: 0x20)
    let mismatching =
        Debuggee.Module(path: "/tmp/a.out", architecture: "arm64",
                        base: Debuggee.Address(rawValue: 0), size: 0x20)
    #expect(request.compatible(matching))
    #expect(request.compatible(mismatching) == false)
  }

  @Test
  internal func modulepath() throws {
#if os(Windows)
    let request = GDBModuleRequest(path: "module.dll", triple: "")
    let path = try request.resolve(working: #"C:\tmp"#)
    #expect(path == #"C:\tmp\module.dll"#)
#else
    let request = GDBModuleRequest(path: "module.so", triple: "")
    let path = try request.resolve(working: "/tmp")
    #expect(path == "/tmp/module.so")
#endif
  }

  @Test
  internal func modules() throws {
    var session = QuerySession()
    let packet =
        #"jModulesInfo:[{"file":"/tmp/a.out","# +
        #""triple":"arm64-unknown-linux"},{"file":"missing","# +
        #""triple":"arm64-unknown-linux"},{"file":"anonymous","# +
        #""triple":"arm64-unknown-linux"},{"file":"C:\\bin\\b.exe","# +
        #""triple":"arm64-unknown-windows"},{"ignored":"value"}]"#
    let response =
        try response(QueryModulesPacket.self, packet: packet, session: &session)
    let expected =
        #"[{"file_path":"/tmp/a.out","file_offset":0,"file_size":32,"# +
        #""triple":"arm64-unknown-linux","uuid":"0123"},{"# +
        #""file_path":"C:\\bin\\b.exe","file_offset":0,"# +
        #""file_size":32,"triple":"arm64-unknown-windows","# +
        #""uuid":"0123"}]"#
    #expect(response == Array(expected.utf8))
  }

  @Test
  internal func advertisement() throws {
    var session = QuerySession()
    let response = try route("qSupported", session: &session)
    let libraries = if DebugCapabilities.current.contains(.images) {
      ""
    } else {
      ";qXfer:libraries:read+"
    }
    let expected =
        "PacketSize=\(kCapacity)\(kWatchpoints);QStartNoAckMode+;" +
        "qXfer:auxv:read+" + libraries
    #expect(response == Array(expected.utf8))
  }

  @Test
  internal func scope() throws {
    let storage = QueryStorage()
    var session = QuerySession(storage)
    let response =
        try response(QueryTransferPacket.self, packet: "qXfer:auxv:read::0,10",
                     session: &session)
    #expect(response == [0x6c, 0xaa])
    #expect(storage.process == ProcessIdentifier(rawValue: 1))
    let thread =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    #expect(storage.thread == thread)
  }

  @Test
  internal func executable() throws {
    let payload = Array("read::10,20".utf8)
    let state =
        GDBRemoteSessionState(compatibility: .gdb, features: [.executable])
    let request =
        try GDBTransferRequest(.executable, payload: payload.span, state: state)
    #expect(request.object == .executable)
    #expect(request.annex.isEmpty)
    #expect(request.offset == 0x10)
    #expect(request.length == 0x20)
  }

  @Test
  internal func process() throws {
    let vendor = Host.metadata.vendor ?? "unknown"
    let platform = Host.metadata.system ?? Host.platform
    let environment = Host.metadata.environment.map { "-\($0)" } ?? ""
    let triple = encode("x86_64-\(vendor)-\(platform)\(environment)")
    let name = encode("inferior")
    var session = QueryProcessSession()
    let current = try response(QueryCurrentProcessInfoPacket.self,
                               packet: "qProcessInfo", session: &session)
    let expected = expected()
    #expect(current == Array(expected.utf8))

    let listed = try response(QueryProcessInfoPacket.self,
                              packet: "qProcessInfoPID:26", session: &session)
    let alternate =
        "pid:26;ppid:10;name:\(name);args:\(encode("/tmp/inferior"))-" +
        "\(encode("10"))-\(encode("qu'o'tes\""))-\(encode("מזל טוב"));" +
        "triple:\(triple);"
    #expect(listed == Array(alternate.utf8))
  }

  @Test
  internal func isolation() throws {
    var session = QueryProcessSession(images: QueryImages(failure: .system(1)))
    let response = try response(QueryCurrentProcessInfoPacket.self,
                                packet: "qProcessInfo", session: &session)
    let expected = expected()
    #expect(response == Array(expected.utf8))
  }

  @Test
  internal func address() throws {
    var session = QueryProcessSession()
    _ = try response(QueryCurrentProcessInfoPacket.self, packet: "qProcessInfo",
                     session: &session)
    let executable = encode("/tmp/inferior")
    let response =
        try response(QueryImagePacket.self,
                     packet: "qFileLoadAddress:\(executable)",
                     session: &session)
    #expect(response == Array("1234".utf8))
  }

  @Test
  internal func fullpath() throws {
    let image =
        Debuggee.Image(path: "/usr/lib/libexample.dylib",
                       base: Debuggee.Address(rawValue: 0x2345))
    var session = QueryProcessSession(images: QueryImages(images: [image]))
    let path = encode("/usr/lib/libexample.dylib")
    let response =
        try response(QueryImagePacket.self, packet: "qFileLoadAddress:\(path)",
                     session: &session)
    #expect(response == Array("2345".utf8))
  }

  @Test
  internal func basename() throws {
    let image =
        Debuggee.Image(path: "/usr/lib/libexample.dylib",
                       base: Debuggee.Address(rawValue: 0x3456))
    var session = QueryProcessSession(images: QueryImages(images: [image]))
    let path = encode("/tmp/libexample.dylib")
    let response =
        try response(QueryImagePacket.self, packet: "qFileLoadAddress:\(path)",
                     session: &session)
    #expect(response == Array("3456".utf8))
  }

  @Test
  internal func backslash() throws {
    let image =
        Debuggee.Image(path: "/usr/lib/libexample.dylib",
                       base: Debuggee.Address(rawValue: 0x4567))
    var session = QueryProcessSession(images: QueryImages(images: [image]))
    let path = encode(#"C:\tmp\libexample.dylib"#)
    let response =
        try response(QueryImagePacket.self, packet: "qFileLoadAddress:\(path)",
                     session: &session)
    #expect(response == Array("4567".utf8))
  }

  @Test
  internal func sensitivity() throws {
    let image =
        Debuggee.Image(path: "/usr/lib/libexample.dylib",
                       base: Debuggee.Address(rawValue: 0x5678))
    var session = QueryProcessSession(images: QueryImages(images: [image]))
    let path = encode("/tmp/LIBEXAMPLE.DYLIB")
#if os(Windows)
    let response =
        try response(QueryImagePacket.self, packet: "qFileLoadAddress:\(path)",
                     session: &session)
    #expect(response == Array("5678".utf8))
#else
    #expect(throws: GDBHandlerError.code(GDBErrorCode.failure)) {
      try response(QueryImagePacket.self, packet: "qFileLoadAddress:\(path)",
                   session: &session)
    }
#endif
  }

  @Test
  internal func malformed() {
    var session = QueryProcessSession()
    #expect(throws: GDBHandlerError.malformed) {
      try response(QueryImagePacket.self, packet: "qFileLoadAddress:0",
                   session: &session)
    }
    #expect(throws: GDBHandlerError.malformed) {
      try response(QueryImagePacket.self, packet: "qFileLoadAddress:0g",
                   session: &session)
    }
  }
}

private func encode(_ value: String) -> String {
  var encoded = ""
  for byte in value.utf8 {
    if byte < 0x10 {
      encoded.append("0")
    }
    encoded.append(String(byte, radix: 16))
  }
  return encoded
}

private func response<Handler>(_ handler: Handler.Type, packet: String,
                               session: inout Handler.Context) throws
    -> Array<UInt8>
    where Handler: GDBPacketHandler & ~Copyable {
  let bytes = Array(packet.utf8)
  var state =
      GDBRemoteSessionState(compatibility: .lldb,
                            features: GDBRemoteFeatures.auxiliary
                              .union(.libraries).union(.noack))
  var response = Array<UInt8>()
  let size = Configuration.PacketCapacity
  try response.append(addingCapacity: size) { output throws(GDBHandlerError) in
    var writer = GDBPacketWriter(consume output)
    do throws(GDBHandlerError) {
      let match = GDBPacketClassifier.classify(bytes.span)
      let payload = bytes.span.extracting(match.payload...)
      _ = try GDBPacketDispatch
        .handle(handler, payload: payload, session: &session, state: &state,
                writer: &writer)
    } catch {
      output = writer.finish()
      throw error
    }
    output = writer.finish()
  }
  return response
}

private func expected() -> String {
  let metadata = Host.metadata
  var response = "pid:1a;parent-pid:a;"
#if !os(anyAppleOS)
  let environment = Host.metadata.environment.map { "-\($0)" } ?? ""
  let triple = encode("x86_64-unknown-\(Host.platform)\(environment)")
  response += "triple:\(triple);"
#endif
  if let cpu = metadata.cpu {
    response += "cputype:\(String(cpu, radix: 16));"
  }
  if let subtype = metadata.subtype {
    response += "cpusubtype:\(String(subtype, radix: 16));"
  }
  if let vendor = metadata.vendor {
    response += "vendor:\(vendor);"
  }
  response += "ostype:\(metadata.system ?? Host.system);"
  response += "endian:little;ptrsize:\(ABI.width.bytes);"
  return response
}

private func route(_ packet: String,
                   session: inout QuerySession) throws -> Array<UInt8> {
  let bytes = Array(packet.utf8)
  var state =
      GDBRemoteSessionState(compatibility: .lldb,
                            features: QueryRouter.features)
  var response = Array<UInt8>()
  let size = Configuration.PacketCapacity
  try response.append(addingCapacity: size) { output throws(GDBHandlerError) in
    var writer = GDBPacketWriter(consume output)
    do throws(GDBHandlerError) {
      let match = GDBPacketClassifier.classify(bytes.span)
      let payload = bytes.span.extracting(match.payload...)
      _ = try QueryRouter.dispatch(match.leaf, payload: payload,
                                   session: &session, state: &state,
                                   writer: &writer)
    } catch {
      output = writer.finish()
      throw error
    }
    output = writer.finish()
  }
  return response
}
