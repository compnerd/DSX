// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal protocol ByteChannel: ~Copyable, Sendable {
  borrowing func wait(_ timeout: Int32,
                      events: borrowing Span<WaitHandle>) throws(TransportError)
      -> WaitResult
  mutating func read(into buffer: inout OutputSpan<UInt8>)
      throws(TransportError)
  mutating func write(_ buffer: borrowing Span<UInt8>) throws(TransportError)
      -> Int
}

extension ByteChannel where Self: ~Copyable {
  internal borrowing func wait(_: Int32, events _: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    .channel
  }
}
