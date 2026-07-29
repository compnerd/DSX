// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemoteNegotiation {
  internal mutating func suffix(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try writer.append("OK")
    enable(.threadsuffix)
    return .reply
  }

  internal mutating func threads(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    try writer.append("OK")
    enable(.stopthreads)
    return .reply
  }

  internal mutating func limit(_ payload: borrowing Span<UInt8>, overhead: Int,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let capacity = try reader.hex()
    // Every accepted limit must accommodate the three-byte error reply.
    guard reader.empty, capacity >= UInt64(overhead + 3),
        capacity <= UInt64(Int.max) else {
      throw .malformed
    }
    try writer.append("OK")
    limit(Int(capacity) - overhead)
  }

  internal mutating func noack(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard supported.contains(.noack) else {
      throw .unsupported
    }
    try writer.append("OK")
    enable(.noack)
    acknowledgements = false
    return .reply
  }
}
