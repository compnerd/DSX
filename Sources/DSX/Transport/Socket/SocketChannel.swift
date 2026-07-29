// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct SocketChannel: ~Copyable, Sendable {
  internal let handle: NativeSocketSystem.Handle

  internal init(_ endpoint: NetworkEndpoint) throws(TransportError) {
    do throws(TransportError) {
      handle = try NativeSocketSystem.connect(endpoint)
    } catch {
      DSX.log("failed to establish network endpoint: \(error)",
              level: .critical, channel: .network)
      throw error
    }
  }

  internal init(_ endpoint: UnixEndpoint) throws(TransportError) {
    do throws(TransportError) {
      handle = try NativeSocketSystem.connect(endpoint)
    } catch {
      DSX.log("failed to establish local endpoint: \(error)", level: .critical,
              channel: .network)
      throw error
    }
  }

  internal init(handle: NativeSocketSystem.Handle) {
    self.handle = handle
  }

  deinit {
    NativeSocketSystem.close(handle, path: nil)
  }

  internal borrowing func wait(_ timeout: Int32,
                               events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    try NativeSocketSystem.wait(handle, timeout: timeout, events: events)
  }

  internal borrowing func read(into bytes: inout OutputSpan<UInt8>)
      throws(TransportError) {
    try NativeSocketSystem.read(handle, into: &bytes)
  }

  internal borrowing func write(_ bytes: borrowing Span<UInt8>)
      throws(TransportError) -> Int {
    try NativeSocketSystem.write(handle, bytes)
  }
}

internal struct SocketListener: ~Copyable, Sendable {
  private typealias Failure = TransportError

  internal let binding: SocketBinding
  internal let handle: NativeSocketSystem.Handle

  internal var bound: UInt16? {
    borrowing get {
      switch binding {
      case .network(let port): port
      case .unix: nil
      }
    }
  }

  internal init(_ endpoint: NetworkEndpoint) throws(TransportError) {
    do throws(TransportError) {
      let result = try NativeSocketSystem.listen(endpoint)
      do {
        try SocketListener.announce(result.port)
      } catch {
        NativeSocketSystem.close(result.handle, path: nil)
        throw error
      }
      binding = .network(result.port)
      handle = result.handle
    } catch {
      DSX.log("failed to establish network endpoint: \(error)",
              level: .critical, channel: .network)
      throw error
    }
  }

  internal init(_ endpoint: UnixEndpoint) throws(TransportError) {
    do throws(TransportError) {
      handle = try NativeSocketSystem.listen(endpoint)
      binding = .unix(endpoint.path)
    } catch {
      DSX.log("failed to establish local endpoint: \(error)", level: .critical,
              channel: .network)
      throw error
    }
  }

  deinit {
    NativeSocketSystem.close(handle, path: binding.path)
  }

  internal borrowing func accept() throws(TransportError) -> SocketChannel {
    try SocketChannel(handle: NativeSocketSystem.accept(handle))
  }

  internal borrowing func wait(_ timeout: Int32,
                               events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    try NativeSocketSystem.wait(handle, timeout: timeout, events: events)
  }

  internal static func announce(_ port: UInt16) throws(TransportError) {
    let type = UInt8.self
    try withUnsafeTemporaryAllocation(of: type,
                                      capacity: 32) { buffer throws(Failure) in
      var count = 0
      var value = port
      let prefix: StaticString = "Listening on port "
      prefix.withUTF8Buffer { bytes in
        for byte in bytes {
          buffer[count] = byte
          count += 1
        }
      }

      var divisor: UInt16 = 10_000
      var started = false
      while divisor > 0 {
        let digit = value / divisor
        if digit > 0 || started || divisor == 1 {
          buffer[count] = UInt8(digit) + 0x30
          count += 1
          started = true
        }
        value %= divisor
        divisor /= 10
      }
      buffer[count] = 0x0a
      count += 1

      try NativeSocketSystem.output(buffer.span.extracting(..<count))
    }
  }
}
