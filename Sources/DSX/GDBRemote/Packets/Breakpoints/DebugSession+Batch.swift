// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private struct GDBBreakpointRequests: ~Escapable {
  private var reader: GDBPacketReader
  private var first = true

  @_lifetime(copy payload)
  fileprivate init(_ payload: consuming Span<UInt8>) throws(GDBHandlerError) {
    reader = GDBPacketReader(payload)
    guard reader.token(UInt8(ascii: "{")),
        reader.consume("\"breakpoint_requests\""),
        reader.token(UInt8(ascii: ":")), reader.token(UInt8(ascii: "[")) else {
      throw .malformed
    }
  }

  @inline(never)
  fileprivate mutating func next() throws(GDBHandlerError) -> Range<Int>? {
    if reader.token(UInt8(ascii: "]")) {
      guard reader.token(UInt8(ascii: "}")), reader.empty else {
        throw .malformed
      }
      return nil
    }
    guard first || reader.token(UInt8(ascii: ",")) else {
      throw .malformed
    }
    first = false
    return try reader.quoted()
  }
}

extension DebugSession {
  internal mutating func breakpoints(_ payload: borrowing Span<UInt8>,
                                     state: borrowing GDBRemoteSessionState,
                                     writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    var requests = try GDBBreakpointRequests(payload.extracting(0...))
    var preview = requests
    let prefix: StaticString = "{\"results\":["
    let suffix: StaticString = "]}"
    let entry: StaticString = ",\"Exx\""
    let envelope = prefix.utf8CodeUnitCount + suffix.utf8CodeUnitCount
    // Reserve the envelope and the largest per-request result before mutation.
    let available = writer.capacity - writer.count
    var count = 0
    while try preview.next() != nil {
      count += 1
    }
    // The first result has no comma; an empty batch still needs its envelope.
    guard available >= envelope,
        count <= (available - envelope + 1) / entry.utf8CodeUnitCount else {
      throw .capacity
    }
    try writer.append(prefix)
    var first = true
    while let request = try requests.next() {
      if first {
        first = false
      } else {
        try writer.append(UInt8(ascii: ","))
      }
      try writer.result(apply(payload.extracting(request), state: state))
    }
    try writer.append(suffix)
    return .reply
  }

  private mutating func apply(_ request: borrowing Span<UInt8>,
                              state: borrowing GDBRemoteSessionState)
      -> UInt8? {
    do throws(GDBHandlerError) {
      guard request.count > 1 else {
        throw .malformed
      }
      let site = try BreakpointSite(request.extracting(1...))
      switch request[0] {
      case UInt8(ascii: "Z"):
        try insert(site, selection: state.selection.general)
      case UInt8(ascii: "z"):
        try remove(site, selection: state.selection.general)
      default:
        throw .malformed
      }
      return nil
    } catch .code(let code) {
      return code
    } catch .debuggee(.access) {
      return GDBErrorCode.access
    } catch {
      return GDBErrorCode.invalid
    }
  }
}

extension GDBPacketWriter {
  fileprivate mutating func result(_ code: UInt8?) throws(GDBHandlerError) {
    try append(UInt8(ascii: "\""))
    if let code {
      try error(code)
    } else {
      try append("OK")
    }
    try append(UInt8(ascii: "\""))
  }
}
