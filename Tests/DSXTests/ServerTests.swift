// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

private let kCapacity = String(Configuration.PacketCapacity, radix: 16)

#if os(anyAppleOS)
internal import Darwin
#endif

@Suite
internal struct ServerTests {
  @Test(arguments: ["1", "yes", "YES", "true", "TRUE", "TrUe"])
  internal func truth(_ value: String) {
    #expect(Daemonization.enabled(value))
  }

  @Test(arguments: ["", "0", "no", "false", "truth", "yes!"])
  internal func falsehood(_ value: String) {
    #expect(Daemonization.enabled(value) == false)
  }

  @Test
  internal func startup() throws {
    try DSX.initialize()
    #expect(DSX.enabled(.info, channel: .system) == false)
  }

  @Test
  internal func servers() {
    let gdb = GDBServer(connection: .descriptor(1))
    let platform =
        PlatformServer(connection: .descriptor(2), multiple: true, port: 1234)
    #expect(gdb.bound == nil)
    #expect(platform.bound == nil)
  }

  @Test
  internal func listener() throws {
    try DSX.initialize()
    let connection = Connection.network("127.0.0.1", port: 0, reverse: false)
    var server = GDBServer(connection: connection)
    try server.start()
    let port = server.bound
    guard let port else {
      Issue.record("listener did not report a bound port")
      return
    }
    #expect(port != 0)
#if os(anyAppleOS)
    let client = socket(AF_INET, SOCK_STREAM, 0)
    #expect(client >= 0)
    defer {
      _ = DSX::close(client)
    }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = UInt16(bigEndian: port)
    address.sin_addr.s_addr = UInt32(bigEndian: INADDR_LOOPBACK)
    let status = withUnsafePointer(to: &address) { address in
      address.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    #expect(status == 0)

    let query = Array("qSupported".utf8)
    let request = frame(query.span)
    let sent = request.withUnsafeBytes { request in
      Darwin.send(client, request.baseAddress, request.count, 0)
    }
    #expect(sent == request.count)
    var remote = try server.accept()
    defer {
      remote.close(.normal)
    }
    try remote.step()

    var expected: Array<UInt8> = [0x2b]
    let supported =
        "PacketSize=\(kCapacity)\(kWatchpoints);QStartNoAckMode+;" +
        "qXfer:features:read+;qXfer:exec-file:read+;" +
        "qXfer:libraries:read+;qXfer:threads:read+;" +
        "QThreadSuffixSupported+;" +
        "QListThreadsInStopReply+;" +
        "QDisableRandomization+;QEnvironmentReset+;" +
        "QEnvironmentUnset+;vContSupported+;swbreak+;hwbreak+;" +
        "QNonStop+;jMultiBreakpoint+;binary-upload+;exec-events+;" +
        "qXfer:memory-map:read+"
    let message = Array(supported.utf8)
    let frame = frame(message.span)
    expected.append(contentsOf: frame)
    var response = Array<UInt8>(repeating: 0, count: expected.count)
    var received = 0
    while received < expected.count {
      let count = response.withUnsafeMutableBytes { response in
        Darwin.recv(client, response.baseAddress?.advanced(by: received),
                    response.count - received, 0)
      }
      guard count > 0 else {
        Issue.record("session response failed")
        return
      }
      received += count
    }
    #expect(received == expected.count)
    #expect(response.elementsEqual(expected))
#endif
  }

  @Test
  internal func multiple() throws {
#if os(anyAppleOS)
    let connection = Connection.network("127.0.0.1", port: 0, reverse: false)
    var server = PlatformServer(connection: connection, multiple: true)
    try server.start()
    let bound = server.bound
    let port = try #require(bound)

    for _ in 0 ..< 2 {
      let client = try client(port)
      let query = Array("qSupported".utf8)
      let request = frame(query.span)
      let sent = request.withUnsafeBytes { request in
        Darwin.send(client, request.baseAddress, request.count, 0)
      }
      #expect(sent == request.count)
      var remote = try server.accept()
      try remote.step()
      _ = shutdown(client, SHUT_WR)
      try remote.serve()
      _ = DSX::close(client)
    }
#endif
  }

  @Test
  internal func failure() {
    DSX.level(.critical)
    defer {
      DSX.level(.off)
    }
    let connection = Connection.network("invalid", port: 0, reverse: false)
    var server = GDBServer(connection: connection)
    #expect(throws: ServerError.self) {
      try server.start()
    }
  }

  @Test
  internal func notification() throws {
#if os(anyAppleOS)
    var descriptors: Array<CInt> = [0, 0]
    try #require(pipe(&descriptors) == 0)
    defer {
      _ = DSX::close(descriptors[0])
      _ = DSX::close(descriptors[1])
    }
    try PortNotifier.write(1234, to: .descriptor(descriptors[1]))
    var bytes = Array<UInt8>(repeating: 0, count: 5)
    let count = bytes.withUnsafeMutableBytes { bytes in
      Darwin.read(descriptors[0], bytes.baseAddress, bytes.count)
    }
    #expect(count == 5)
    #expect(bytes.elementsEqual(Array("1234\n".utf8)))
#endif
  }

  @Test
  internal func logging() throws {
    let configuration =
        try LogConfiguration.parse("gdb-remote packets:lldb process:warning")
    #expect(configuration.level == .warning)
    let channels = LogChannel.packet.bit | LogChannel.process.bit
    #expect(configuration.channels == channels)
    #expect(throws: LogConfigurationError.self) {
      try LogConfiguration.parse("unknown")
    }
  }
}

private func frame(_ message: borrowing Span<UInt8>) -> Array<UInt8> {
  var frame = Array<UInt8>()
  let capacity = GDBPacketFraming.capacity(message.count)
  frame.append(addingCapacity: capacity) { output in
    GDBPacketFraming.frame(message, encoding: .text, output: &output)
  }
  return frame
}

#if os(anyAppleOS)
private func client(_ port: UInt16) throws -> CInt {
  let client = socket(AF_INET, SOCK_STREAM, 0)
  try #require(client >= 0)
  var address = sockaddr_in()
  address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
  address.sin_family = sa_family_t(AF_INET)
  address.sin_port = UInt16(bigEndian: port)
  address.sin_addr.s_addr = UInt32(bigEndian: INADDR_LOOPBACK)
  let status = withUnsafePointer(to: &address) { address in
    address.withMemoryRebound(to: sockaddr.self, capacity: 1) {
      Darwin.connect(client, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
    }
  }
  try #require(status == 0)
  return client
}
#endif
