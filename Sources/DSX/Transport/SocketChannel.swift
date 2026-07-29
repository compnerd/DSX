// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct SocketChannel: ~Copyable, Sendable {
  internal let handle: NativeSocket.Handle

  internal init(_ endpoint: NetworkEndpoint) throws(TransportError) {
    do throws(TransportError) {
      handle = try NativeSocket.connect(endpoint)
    } catch {
      DSX.log("failed to establish network endpoint: \(error)",
              level: .critical, channel: .network)
      throw error
    }
  }

  internal init(_ endpoint: UnixEndpoint) throws(TransportError) {
    do throws(TransportError) {
      handle = try NativeSocket.connect(endpoint)
    } catch {
      DSX.log("failed to establish local endpoint: \(error)", level: .critical,
              channel: .network)
      throw error
    }
  }

  internal init(handle: NativeSocket.Handle) {
    self.handle = handle
  }

  deinit {
    NativeSocket.close(handle, path: nil)
  }

  internal borrowing func wait(timeout: Int32,
                               events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    try NativeSocket.wait(handle, timeout: timeout, events: events)
  }

  internal borrowing func read(into bytes: inout OutputSpan<UInt8>)
      throws(TransportError) {
    try bytes
      .withUnsafeMutableBufferPointer { data, offset throws(TransportError) in
      let base = data.baseAddress!.advanced(by: offset)
      offset += try NativeSocket.receive(handle, into: base,
                                         capacity: data.count - offset)
    }
  }

  internal borrowing func write(_ bytes: borrowing Span<UInt8>)
      throws(TransportError) -> Int {
    if bytes.isEmpty {
      return 0
    }
    return try bytes.withUnsafeBytes { bytes throws(TransportError) in
      try NativeSocket.transmit(handle, from: bytes.baseAddress!,
                                count: bytes.count)
    }
  }
}
