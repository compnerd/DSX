// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee.Thread.Selection {
  internal init(_ payload: borrowing Span<UInt8>, debuggee: borrowing Debuggee)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    if reader.consume("-1") {
      guard reader.empty else {
        throw .malformed
      }
      self = .all
      return
    }
    if payload.count == 1, reader.consume("0") {
      guard reader.empty else {
        throw .malformed
      }
      self = .any
      return
    }
    if reader.consume(UInt8(ascii: "p")) {
      if reader.consume("-1") {
        if reader.empty {
          self = .all
          return
        }
        guard reader.consume(UInt8(ascii: ".")) else {
          throw .malformed
        }
        if reader.consume("-1") || reader.consume("0") {
          guard reader.empty else {
            throw .malformed
          }
          self = .all
          return
        }
        _ = try reader.hex()
        guard reader.empty else {
          throw .malformed
        }
        throw .debuggee(.process)
      }
      if reader.consume("0") {
        guard reader.consume(UInt8(ascii: ".")) else {
          throw .malformed
        }
        let selection = try reader.special()
        guard reader.empty else {
          throw .malformed
        }
        self = selection
        return
      }
      let process = try ProcessIdentifier(rawValue: reader.hex())
      if reader.count > 0 {
        guard reader.consume(UInt8(ascii: ".")), reader.count > 0 else {
          throw .malformed
        }
      }
      if reader.empty || reader.consume("-1") || reader.consume("0") {
        guard reader.empty else {
          throw .malformed
        }
        guard debuggee.contains(process) else {
          throw .debuggee(.process)
        }
        if case .exited = debuggee.state(process) {
          throw .debuggee(.process)
        }
        self = .process(process)
        return
      }
      let thread = try ThreadIdentifier(rawValue: reader.hex())
      guard reader.empty else {
        throw .malformed
      }
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      guard debuggee.alive(identifier) else {
        throw .debuggee(.thread)
      }
      self = .thread(identifier)
      return
    }

    let thread = try ThreadIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    guard let identifier = debuggee.resolve(thread) else {
      throw .debuggee(.thread)
    }
    self = .thread(identifier)
  }
}

extension ProcessThreadIdentifier {
  internal func size(multiprocess: Bool) -> Int {
    if multiprocess {
      let process = process.rawValue.digits
      let thread = thread.rawValue.digits
      return 2 + process + thread
    }
    return thread.rawValue.digits
  }
}

extension GDBPacketWriter {
  internal mutating func thread(_ identifier: ProcessThreadIdentifier,
                                multiprocess: Bool) throws(GDBHandlerError) {
    if multiprocess {
      try append(UInt8(ascii: "p"))
      try hex(identifier.process.rawValue)
      try append(UInt8(ascii: "."))
    }
    try hex(identifier.thread.rawValue)
  }
}

extension Debuggee.Thread.Selection {
  internal func process(in debuggee: borrowing Debuggee) throws(GDBHandlerError)
      -> ProcessIdentifier {
    guard let process = debuggee.process(self) else {
      throw .debuggee(.process)
    }
    return process
  }
}

extension GDBPacketReader {
  fileprivate mutating func special() throws(GDBHandlerError)
      -> Debuggee.Thread.Selection {
    if consume("-1") {
      return .all
    }
    guard consume("0") else {
      throw .debuggee(.process)
    }
    return .any
  }
}
