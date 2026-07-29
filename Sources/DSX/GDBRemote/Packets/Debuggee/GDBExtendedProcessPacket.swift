// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  @inline(__always)
  internal mutating func terminate(_ payload: borrowing Span<UInt8>,
                                   state: inout GDBRemoteSessionState,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try process(payload, state: state)
    try translate(terminate(process))
    state.termination = .extended(process)
  }
}

extension DebugSession {
  private borrowing func process(_ payload: borrowing Span<UInt8>,
                                 state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) -> ProcessIdentifier {
    guard payload.count > 0 else {
      return try state.selection.resume.process(in: debuggee)
    }
    var reader = GDBPacketReader(payload.extracting(0...))
    guard reader.consume(UInt8(ascii: ";")) else {
      throw .malformed
    }
    let process = try ProcessIdentifier(rawValue: reader.hex())
    guard reader.empty, debuggee.contains(process) else {
      throw .debuggee(.process)
    }
    return process
  }
}

internal enum GDBAttachPolicy: Equatable {
  case either
  case future
  case now
}

internal enum GDBNamedAttachPlan {
  case attach(ProcessIdentifier)
  case queue(String, existing: Bool)
}

extension DebugSession {
  internal mutating func attach(_ payload: borrowing Span<UInt8>,
                                policy: GDBAttachPolicy)
      throws(GDBHandlerError) {
    let plan = try GDBNamedAttachPlan(payload, policy: policy)
    switch plan {
    case .attach(let process):
      try translate(attach(process))
    case .queue(let name, let existing):
      try translate(queue(name, existing: existing))
    }
  }
}

extension GDBNamedAttachPlan {
  internal init(_ payload: borrowing Span<UInt8>, policy: GDBAttachPolicy)
      throws(GDBHandlerError) {
    guard payload.count > 0 else {
      throw .malformed
    }
    let name = try String(hex: payload)
    if policy == .future {
      self = .queue(name, existing: true)
      return
    }
    var lookup = try translate(ProcessLookup(name))
    let process = try translate(lookup.first(excluding: []))
    guard let process else {
      guard policy == .either else {
        throw .debuggee(.process)
      }
      self = .queue(name, existing: false)
      return
    }
    self = .attach(process)
  }
}
