// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  @inline(__always)
  internal borrowing func cache(_ payload: borrowing Span<UInt8>,
                                state: borrowing GDBRemoteSessionState,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    guard payload.isEmpty || reader.consume("{}") && reader.empty else {
      throw .malformed
    }
    if payload.isEmpty {
      return try writer.append("OK")
    }
    let process = try state.selection.general.process(in: self)
    let cache = try translate(process.cache)
    try writer.append("{\"shared_cache_base_address\":")
    try writer.decimal(cache.base.rawValue)
    try writer.append(",\"shared_cache_uuid\":\"")
    try writer.json(cache.identifier)
    try writer.append("\",\"no_shared_cache\":")
    try writer.append(cache.absent ? "true" : "false")
    try writer.append(",\"shared_cache_private_cache\":")
    try writer.append(cache.isolated ? "true" : "false")
    if let path = cache.path {
      try writer.append(",\"shared_cache_path\":\"")
      try writer.json(path)
      try writer.append(UInt8(ascii: "\""))
    }
    try writer.append(UInt8(ascii: "}"))
  }
}
