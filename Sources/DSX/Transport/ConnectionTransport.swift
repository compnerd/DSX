// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum ConnectionTransport: ~Copyable, Sendable {
  case socket(SocketChannel)
  case stream(Stream)

  internal borrowing func wait(_ timeout: Int32,
                               events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    switch self {
    case .socket(let socket):
      try socket.wait(timeout, events: events)
    case .stream(let stream):
      try stream.wait(timeout, events: events)
    }
  }

  internal borrowing func read(into bytes: inout OutputSpan<UInt8>)
      throws(TransportError) {
    switch self {
    case .socket(let socket):
      try socket.read(into: &bytes)
    case .stream(let stream):
      try stream.read(into: &bytes)
    }
  }

  internal borrowing func write(_ bytes: borrowing Span<UInt8>)
      throws(TransportError) -> Int {
    switch self {
    case .socket(let socket):
      try socket.write(bytes)
    case .stream(let stream):
      try stream.write(bytes)
    }
  }
}

internal struct ConnectionAcceptance: ~Copyable, Sendable {
  internal var listener: SocketListener?
  internal var transport: ConnectionTransport

  internal init(listener: consuming SocketListener?,
                transport: consuming ConnectionTransport) {
    self.listener = consume listener
    self.transport = consume transport
  }
}

internal enum ConnectionEndpoint: ~Copyable, Sendable {
  case listener(SocketListener)
  case ready(ConnectionTransport)

  internal init(_ connection: consuming Connection) throws(TransportError) {
    self = switch consume connection {
    case .descriptor(let descriptor):
      try .ready(.stream(Stream(.descriptor(descriptor))))
    case .device(let path):
      try .ready(.stream(Stream(.device(path))))
    case .pipe(let path):
      try .ready(.stream(Stream(.pipe(path))))
    case .network(let host, let port, let reverse):
      try ConnectionEndpoint.network(host: consume host, port: port,
                                     reverse: reverse)
    case .unix(let path, let reverse):
      try ConnectionEndpoint.local(path: consume path, reverse: reverse)
    }
  }

  private static func network(host: consuming String?, port: UInt16,
                              reverse: Bool) throws(TransportError)
      -> ConnectionEndpoint {
    let endpoint = NetworkEndpoint(host: consume host, port: port)
    if reverse {
      return try .ready(.socket(SocketChannel(endpoint)))
    }
    return try .listener(SocketListener(endpoint))
  }

  private static func local(path: consuming String, reverse: Bool)
      throws(TransportError) -> ConnectionEndpoint {
    let endpoint = UnixEndpoint(path: consume path)
    if reverse {
      return try .ready(.socket(SocketChannel(endpoint)))
    }
    return try .listener(SocketListener(endpoint))
  }

  internal var bound: UInt16? {
    borrowing get {
      switch self {
      case .listener(let socket): socket.bound
      case .ready: nil
      }
    }
  }

  internal borrowing func wait(_ timeout: Int32,
                               events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    switch self {
    case .listener(let listener):
      try listener.wait(timeout, events: events)
    case .ready:
      .channel
    }
  }

  internal consuming func accept() throws(TransportError)
      -> ConnectionAcceptance {
    switch consume self {
    case .listener(let listener):
      let channel = try listener.accept()
      return ConnectionAcceptance(listener: consume listener,
                                  transport: .socket(consume channel))
    case .ready(let transport):
      return ConnectionAcceptance(listener: nil, transport: consume transport)
    }
  }
}

extension ConnectionTransport: ByteChannel {
}
