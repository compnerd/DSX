// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

/// Replies retained until the client acknowledges their notification.
internal struct GDBRemoteNotifications: ~Copyable, Sendable {
  private var replies = Array<Array<UInt8>>()
  private var cursor = 0

  internal var first: Array<UInt8>? {
    cursor < replies.count ? replies[cursor] : nil
  }

  internal mutating func reset() {
    replies.removeAll(keepingCapacity: true)
    cursor = 0
  }

  internal mutating func restart() {
    // A new ? snapshot must preserve unacknowledged process exits.
    replies.removeFirst(cursor)
    replies.removeAll { reply in
      reply.first != UInt8(ascii: "W") && reply.first != UInt8(ascii: "X")
    }
    cursor = 0
  }

  internal mutating func record(_ reply: borrowing Span<UInt8>) {
    replies.append(reply.withUnsafeBufferPointer { Array($0) })
  }

  internal mutating func acknowledge(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard cursor < replies.count else {
      throw .code(GDBErrorCode.state)
    }
    if cursor + 1 < replies.count {
      let reply = replies[cursor + 1]
      try writer.append(reply.span)
    } else {
      try writer.append("OK")
    }
    // Commit the acknowledgement only after its response can be delivered.
    // Release acknowledged payloads even while new reports keep arriving.
    replies[cursor] = []
    cursor += 1
    if cursor >= replies.count {
      return reset()
    }
    if cursor >= replies.count / 2 {
      replies.removeFirst(cursor)
      cursor = 0
    }
  }
}
