// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBRegisterRequest {
  internal let range: Range<Int>
  internal let thread: ProcessThreadIdentifier

  internal init(_ payload: borrowing Span<UInt8>, debuggee: borrowing Debuggee,
                state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let enabled = state.negotiation.enabled.contains(.threadsuffix)
    let field: Range<Int>? =
        if enabled { try? reader.field(UInt8(ascii: ";")) } else { nil }
    range = field ?? (0 ..< payload.count)
    var requested: ProcessThreadIdentifier?
    if let field {
      let trailing = payload[payload.count - 1] == UInt8(ascii: ";")
      let end = payload.count - (trailing ? 1 : 0)
      guard field.upperBound < end else {
        throw .malformed
      }
      var suffix =
          GDBPacketReader(payload.extracting(field.upperBound + 1 ..< end))
      guard suffix.consume("thread:") else {
        throw .malformed
      }
      let selection =
          try Debuggee.Thread.Selection(suffix.remaining(), debuggee: debuggee)
      guard case .thread(let identifier) = selection else {
        throw .debuggee(.thread)
      }
      requested = identifier
    }
    thread = try state.selection.thread(requested, in: debuggee)
  }
}

extension DebugSession {
  internal borrowing func description(_ state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) -> RegisterDescription {
    try RegisterDescription { () throws(GDBHandlerError) in
      let thread = try state.selection.thread(nil, in: debuggee)
      return try thread.snapshot()
    }
  }
}
