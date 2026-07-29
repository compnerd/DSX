// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum ConnectionTransport: ~Copyable, Sendable {
  case socket(SocketChannel)
  case stream(Stream)

  internal borrowing func wait(timeout: Duration?,
                               events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    switch self {
    case let .socket(socket):
      try socket.wait(timeout: timeout, events: events)
    case let .stream(stream):
      try stream.wait(timeout: timeout, events: events)
    }
  }

  internal borrowing func read(into bytes: inout OutputSpan<UInt8>)
      throws(TransportError) {
    switch self {
    case let .socket(socket):
      try socket.read(into: &bytes)
    case let .stream(stream):
      try stream.read(into: &bytes)
    }
  }

  internal borrowing func write(_ bytes: borrowing Span<UInt8>)
      throws(TransportError) -> Int {
    switch self {
    case let .socket(socket):
      try socket.write(bytes)
    case let .stream(stream):
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
    case let .descriptor(descriptor):
      try .ready(.stream(Stream(.descriptor(descriptor))))
    case let .device(path):
      try .ready(.stream(Stream(.device(path))))
    case let .pipe(path):
      try .ready(.stream(Stream(.pipe(path))))
    case let .network(host, port, reverse):
      try ConnectionEndpoint(NetworkEndpoint(host: consume host, port: port),
                             reverse: reverse)
    case let .unix(path, reverse):
      try ConnectionEndpoint(UnixEndpoint(consume path), reverse: reverse)
    }
  }

  private init(_ endpoint: NetworkEndpoint, reverse: Bool)
      throws(TransportError) {
    self = if reverse {
      try .ready(.socket(SocketChannel(endpoint)))
    } else {
      try .listener(SocketListener(endpoint))
    }
  }

  private init(_ endpoint: UnixEndpoint, reverse: Bool) throws(TransportError) {
    self = if reverse {
      try .ready(.socket(SocketChannel(endpoint)))
    } else {
      try .listener(SocketListener(endpoint))
    }
  }

  internal var bound: UInt16? {
    borrowing get {
      switch self {
      case let .listener(socket): socket.bound
      case .ready: nil
      }
    }
  }

  internal borrowing func wait(timeout: Duration?,
                               events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    switch self {
    case let .listener(listener):
      try listener.wait(timeout: timeout, events: events)
    case .ready:
      .channel
    }
  }

  internal consuming func accept() throws(TransportError)
      -> ConnectionAcceptance {
    switch consume self {
    case let .listener(listener):
      let channel = try listener.accept()
      return ConnectionAcceptance(listener: consume listener,
                                  transport: .socket(consume channel))
    case let .ready(transport):
      return ConnectionAcceptance(listener: nil, transport: consume transport)
    }
  }
}
