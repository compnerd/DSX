// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee.Launch {
  internal mutating func directory(_ payload: borrowing Span<UInt8>,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let path = try String(hex: payload)
    try writer.append("OK")
    directory = path
  }
}

extension Debuggee.Launch {
  internal mutating func arguments(_ payload: borrowing Span<UInt8>,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var start = 0
    while start < payload.count, payload[start] == UInt8(ascii: " ") {
      start += 1
    }
    guard start < payload.count else {
      throw .malformed
    }
    switch payload[start] {
    case UInt8(ascii: "0") ... UInt8(ascii: "9"):
      break
    default:
      throw .unsupported
    }
    var reader = GDBPacketReader(payload.extracting(0...))
    var arguments = Array<String>()
    while reader.count > 0 {
      while reader.consume(UInt8(ascii: " ")) {
      }
      let length = try reader.decimal()
      guard reader.consume(UInt8(ascii: ",")), length <= UInt64(Int.max) else {
        throw .malformed
      }
      let ordinal = try reader.decimal()
      guard reader.consume(UInt8(ascii: ",")),
          ordinal < UInt64(Configuration.ResumeActionCapacity) else {
        throw .capacity
      }
      let range = try reader.take(Int(length))
      let argument = try String(hex: reader.span(range))
      let index = Int(ordinal)
      while arguments.count <= index {
        arguments.append("")
      }
      arguments[index] = argument
      if reader.count > 0 {
        guard reader.consume(UInt8(ascii: ",")) else {
          throw .malformed
        }
      }
    }
    guard !arguments.isEmpty else {
      throw .malformed
    }
    try writer.append("OK")
    executable = arguments.removeFirst()
    self.arguments = consume arguments
  }
}

extension DebugSession {
  internal mutating func arguments(_ payload: borrowing Span<UInt8>,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try launch.arguments(payload, writer: &writer)
    do throws(Debuggee.Error) {
      _ = try spawn()
      try settle()
    } catch {
      error.log("failed to launch debuggee from A packet")
      throw .debuggee(error)
    }
  }
}

extension Debuggee.Launch {
  internal mutating func environment(_ payload: borrowing Span<UInt8>,
                                     writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let value = try String(hex: payload)
    try environment(value, writer: &writer)
  }

  internal mutating func environment(raw payload: borrowing Span<UInt8>,
                                     writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let value = String(decoding: payload, as: UTF8.self)
    try environment(value, writer: &writer)
  }

  internal mutating func environment(reset payload: borrowing Span<UInt8>,
                                     writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    try writer.append("OK")
    environment.removeAll(keepingCapacity: true)
  }

  internal mutating func environment(unset payload: borrowing Span<UInt8>,
                                     writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let name = try String(hex: payload)
    let entry = Debuggee.Environment(name: name, value: nil)
    try writer.append("OK")
    try set(entry)
  }

  private mutating func environment(_ value: String,
                                    writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard let separator = value.firstIndex(of: "=") else {
      throw .malformed
    }
    let name = String(value[..<separator])
    let start = value.index(after: separator)
    let entry = Debuggee.Environment(name: name, value: String(value[start...]))
    try writer.append("OK")
    try set(entry)
  }
}

extension Debuggee.Launch {
  internal mutating func aslr(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.count == 1 else {
      throw .malformed
    }
    guard payload[0] == UInt8(ascii: "0") ||
        payload[0] == UInt8(ascii: "1") else {
      throw .malformed
    }
    try writer.append("OK")
    aslr = payload[0] == UInt8(ascii: "0")
  }
}

extension Debuggee.Launch {
  internal mutating func run(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    var executable = executable
    var arguments = Array<String>()
    if reader.empty == false {
      guard reader.consume(UInt8(ascii: ";")) else {
        throw .malformed
      }
      let field = reader.prefix(UInt8(ascii: ";"))
      let filename = try String(hex: reader.span(field))
      if filename.isEmpty == false {
        executable = filename
      }
      while reader.consume(UInt8(ascii: ";")) {
        let field = reader.prefix(UInt8(ascii: ";"))
        try arguments.append(String(hex: reader.span(field)))
      }
    }
    guard let executable, executable.isEmpty == false else {
      throw .debuggee(.process)
    }
    self.executable = executable
    self.arguments = consume arguments
  }
}

extension Debuggee.Launch {
  internal mutating func set(_ entry: consuming Debuggee.Environment)
      throws(GDBHandlerError) {
    guard entry.valid else {
      throw .malformed
    }
    if let index = environment.firstIndex(where: { value in
      Host.precedes(value.name, entry.name) == false &&
          Host.precedes(entry.name, value.name) == false
    }) {
      environment[index] = entry
    } else {
      environment.append(entry)
    }
  }
}
