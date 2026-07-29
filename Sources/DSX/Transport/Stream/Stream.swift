// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum StreamEndpoint: Sendable {
  case descriptor(CInt)
  case device(String)
  case notification(String)
  case pipe(String)
}

internal struct Stream: ~Copyable, @unchecked Sendable {
  internal let handle: NativeStream.Handle
  internal let owned: Bool

  internal init(_ endpoint: StreamEndpoint) throws(TransportError) {
    owned = switch endpoint {
    case .descriptor:
      false
    case .device, .notification, .pipe:
      true
    }
    do {
      handle = try NativeStream.open(endpoint)
    } catch {
      DSX.log("failed to establish stream endpoint: \(error)", level: .critical,
              channel: .system)
      throw error
    }
  }

  deinit {
    if owned {
      NativeStream.close(handle)
    }
  }

  internal borrowing func wait(_ timeout: Int32,
                               events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    try NativeStream.wait(handle, timeout: timeout, events: events)
  }

  internal borrowing func read(into bytes: inout OutputSpan<UInt8>)
      throws(TransportError) {
    try bytes
      .withUnsafeMutableBufferPointer { data, offset throws(TransportError) in
      let base = data.baseAddress!.advanced(by: offset)
      offset += try NativeStream.receive(handle, base, data.count - offset)
    }
  }

  internal borrowing func write(_ bytes: borrowing Span<UInt8>)
      throws(TransportError) -> Int {
    if bytes.isEmpty {
      return 0
    }
    return try bytes.withUnsafeBytes { bytes throws(TransportError) in
      try NativeStream.transmit(handle, bytes.baseAddress!, bytes.count)
    }
  }
}
