// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

@Suite
internal struct TransportTests {
  @Test
  internal func descriptor() {
    var server = GDBServer(connection: .descriptor(CInt.max))
    #expect(throws: ServerError.self) {
      try server.start()
    }
  }

#if !os(Windows)
  @Test
  internal func inheritance() throws {
    let listener =
        try SocketListener(NetworkEndpoint(host: "127.0.0.1", port: 0))
    guard let port = listener.bound else {
      Issue.record("expected a bound network port")
      return
    }
    let client =
        try SocketChannel(NetworkEndpoint(host: "127.0.0.1", port: port))
    let peer = try listener.accept()
    #expect(fcntl(listener.handle, F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
    #expect(fcntl(client.handle, F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
    #expect(fcntl(peer.handle, F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
  }

  @Test
  internal func device() throws {
    let stream = try Stream(.device("/dev/null"))
    #expect(fcntl(stream.handle, F_GETFL) & O_NONBLOCK == 0)
    var server = GDBServer(connection: .device("/dev/null"))
    try server.start()
    var remote = try server.accept()
    remote.close(.normal)
  }

  @Test
  internal func pipe() throws {
    let path = "/tmp/dsx-\(getpid()).fifo"
    path.withCString {
      _ = unlink($0)
    }
    defer {
      path.withCString {
        _ = unlink($0)
      }
    }
    #expect(path.withCString { mkfifo($0, 0o600) } == 0)
    var server = GDBServer(connection: .pipe(path))
    try server.start()
    var remote = try server.accept()
    remote.close(.normal)
  }

  @Test
  internal func unix() throws {
    let path = "/tmp/dsx-\(getpid()).sock"
    path.withCString {
      _ = unlink($0)
    }
    do {
      var server = GDBServer(connection: .unix(path, reverse: false))
      try server.start()
      #expect(path.withCString { access($0, F_OK) } == 0)
      let client = try local(path)
      defer {
        _ = DSX::close(client)
      }
      var remote = try server.accept()
      remote.close(.normal)
    }
    #expect(path.withCString { access($0, F_OK) } == -1)
  }
#endif
}

#if !os(Windows)
private func local(_ path: String) throws -> CInt {
  let handle = socket(AF_UNIX, BSDSocketAPI.stream, 0)
  #expect(handle >= 0)
  var address = sockaddr_un()
#if os(anyAppleOS) || os(FreeBSD) || os(OpenBSD)
  address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
#endif
  address.sun_family = sa_family_t(AF_UNIX)
  let count = path.utf8.count
  path.withCString { source in
    withUnsafeMutableBytes(of: &address.sun_path) { destination in
      destination.copyBytes(from: UnsafeRawBufferPointer(start: source,
                                                         count: count + 1))
    }
  }
  let status = withUnsafePointer(to: &address) { address in
    address.withMemoryRebound(to: sockaddr.self, capacity: 1) {
#if os(anyAppleOS)
      Darwin.connect(handle, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
#elseif os(Android)
      Android.connect(handle, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
      Glibc.connect(handle, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
#endif
    }
  }
  #expect(status == 0)
  return handle
}
#endif
