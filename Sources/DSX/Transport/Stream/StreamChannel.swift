// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct Stream: ~Copyable, @unchecked Sendable {
  internal let handle: NativeStreamSystem.Handle
  internal let owned: Bool

  internal init(_ endpoint: StreamEndpoint) throws(TransportError) {
    owned = switch endpoint {
    case .descriptor:
      false
    case .device, .notification, .pipe:
      true
    }
    do {
      handle = try NativeStreamSystem.open(endpoint)
    } catch {
      DSX.log("failed to establish stream endpoint: \(error)", level: .critical,
              channel: .system)
      throw error
    }
  }

  deinit {
    if owned {
      NativeStreamSystem.close(handle)
    }
  }

  internal borrowing func wait(_ timeout: Int32,
                               events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    try NativeStreamSystem.wait(handle, timeout: timeout, events: events)
  }

  internal borrowing func read(into bytes: inout OutputSpan<UInt8>)
      throws(TransportError) {
    try NativeStreamSystem.read(handle, into: &bytes)
  }

  internal borrowing func write(_ bytes: borrowing Span<UInt8>)
      throws(TransportError) -> Int {
    try NativeStreamSystem.write(handle, bytes)
  }
}
