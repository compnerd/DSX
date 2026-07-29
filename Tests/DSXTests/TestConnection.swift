// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX
#if os(Windows)
internal import WinSDK
#elseif os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

/// A real loopback peer for exercising the production transport and framing.
internal final class TestConnection {
  private let peer: SocketChannel
  private var accepted: NativeSocket.Handle?
  private var received = Array<UInt8>()

  internal init(_ input: Array<UInt8> = []) throws {
#if os(Windows)
    var data = WSADATA()
    let status = WSAStartup(WORD(0x0202), &data)
    #expect(status == 0)
#endif
    let endpoint = NetworkEndpoint(host: "127.0.0.1", port: 0)
    let listener = try NativeSocket.listen(endpoint)
    defer { NativeSocket.close(listener.handle, path: nil) }
    peer = try SocketChannel(NetworkEndpoint(host: "127.0.0.1",
                                             port: listener.port))
    accepted = try NativeSocket.accept(listener.handle, network: true)
    try send(input)
  }

  deinit {
    if let accepted {
      NativeSocket.close(accepted, path: nil)
    }
  }

  internal func connect() -> ConnectionTransport {
    let handle = accepted!
    accepted = nil
    return .socket(SocketChannel(handle: handle))
  }

  internal func send(_ bytes: Array<UInt8>) throws(TransportError) {
    var offset = 0
    while offset < bytes.count {
      offset += try peer.write(bytes.span.extracting(offset...))
    }
  }

  internal func finish() {
#if os(Windows)
    #expect(shutdown(peer.handle, SD_SEND) == 0)
#else
    #expect(shutdown(peer.handle, CInt(SHUT_WR)) == 0)
#endif
  }

  internal var output: Array<UInt8> {
    get {
      do {
        while try peer.wait(5, events: Span()) == .channel {
          let start = received.count
          try received.append(addingCapacity: 65536) { output in
            try self.peer.read(into: &output)
          }
          if received.count == start {
            break
          }
        }
      } catch {
        Issue.record("loopback receive failed: \(error)")
      }
      return received
    }
    set { received = newValue }
  }
}
