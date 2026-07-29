// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBThreadIdentifier {
  internal static func parse(_ payload: borrowing Span<UInt8>,
                             debuggee: borrowing Debuggee)
      throws(GDBHandlerError) -> Debuggee.Thread.Selection {
    var reader = GDBPacketReader(payload.extracting(0...))
    if reader.consume("-1") {
      guard reader.empty else {
        throw .malformed
      }
      return .all
    }
    if payload.count == 1, reader.consume("0") {
      guard reader.empty else {
        throw .malformed
      }
      return .any
    }
    if reader.consume(UInt8(ascii: "p")) {
      if reader.consume("-1") {
        guard reader.consume(UInt8(ascii: ".")) else {
          throw .malformed
        }
        if reader.consume("-1") || reader.consume("0") {
          guard reader.empty else {
            throw .malformed
          }
          return .all
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
        let selection = try special(&reader)
        guard reader.empty else {
          throw .malformed
        }
        return selection
      }
      let process = try ProcessIdentifier(rawValue: reader.hex())
      guard reader.consume(UInt8(ascii: ".")) else {
        throw .malformed
      }
      if reader.consume("-1") || reader.consume("0") {
        guard reader.empty else {
          throw .malformed
        }
        guard debuggee.contains(process) else {
          throw .debuggee(.process)
        }
        return .process(process)
      }
      let thread = try ThreadIdentifier(rawValue: reader.hex())
      guard reader.empty else {
        throw .malformed
      }
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      guard debuggee.contains(identifier) else {
        throw .debuggee(.thread)
      }
      return .thread(identifier)
    }

    let thread = try ThreadIdentifier(rawValue: reader.hex())
    guard reader.empty else {
      throw .malformed
    }
    guard let identifier = debuggee.resolve(thread) else {
      throw .debuggee(.thread)
    }
    return .thread(identifier)
  }

  internal static func size(_ identifier: ProcessThreadIdentifier,
                            multiprocess: Bool) -> Int {
    if multiprocess {
      let process = digits(identifier.process.rawValue)
      let thread = digits(identifier.thread.rawValue)
      return 2 + process + thread
    }
    return digits(identifier.thread.rawValue)
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

extension GDBThreadIdentifier {
}

internal enum GDBPacketScope {
  internal static func process(_ selection: Debuggee.Thread.Selection,
                               debuggee: borrowing Debuggee)
      throws(GDBHandlerError) -> ProcessIdentifier {
    guard let process = debuggee.process(selection) else {
      throw .debuggee(.process)
    }
    return process
  }

  internal static func thread(_ selection: Debuggee.Thread.Selection,
                              fallback: ProcessThreadIdentifier?,
                              debuggee: borrowing Debuggee)
      -> ProcessThreadIdentifier? {
    if let resolved = debuggee.resolve(selection) {
      return resolved
    }
    guard let fallback, debuggee.alive(fallback) else {
      return nil
    }
    return fallback
  }

  internal static func thread(_ requested: ProcessThreadIdentifier?,
                              selection: Debuggee.Thread.Selection,
                              fallback: ProcessThreadIdentifier?,
                              debuggee: borrowing Debuggee)
      throws(GDBHandlerError) -> ProcessThreadIdentifier {
    if let requested {
      return requested
    }
    let selected = thread(selection, fallback: fallback, debuggee: debuggee)
    guard let selected else {
      throw .debuggee(.thread)
    }
    return selected
  }

  internal static func scope(_ selection: Debuggee.Thread.Selection,
                             fallback: ProcessThreadIdentifier?,
                             debuggee: borrowing Debuggee)
      -> (ProcessIdentifier?, ProcessThreadIdentifier?) {
    let process = debuggee.process(selection)
    let thread = thread(selection, fallback: fallback, debuggee: debuggee)
    return (process, thread)
  }
}

private func special(_ reader: inout GDBPacketReader) throws(GDBHandlerError)
    -> Debuggee.Thread.Selection {
  if reader.consume("-1") {
    return .all
  }
  guard reader.consume("0") else {
    throw .debuggee(.process)
  }
  return .any
}

private func digits(_ value: UInt64) -> Int {
  var value = value
  var count = 1
  while value >= 16 {
    value >>= 4
    count += 1
  }
  return count
}
