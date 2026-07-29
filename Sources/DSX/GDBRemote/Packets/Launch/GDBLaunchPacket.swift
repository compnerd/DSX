// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBWorkingDirectoryPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              launch: inout Debuggee.Launch,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    launch.working = try GDBPacketReader.string(payload)
    try writer.append("OK")
  }
}

internal enum GDBArgumentsPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              launch: inout Debuggee.Launch,
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
      let argument = try GDBPacketReader.string(reader.span(range))
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
    launch.executable = arguments.removeFirst()
    launch.arguments = consume arguments
    try writer.append("OK")
  }

  internal static func launch(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    _ = try handle(payload, launch: &session.launch, writer: &writer)
    do throws(Debuggee.Error) {
      _ = try session.spawn()
      try session.settle()
    } catch {
      DSX.log("failed to launch debuggee from A packet: \(error)",
              level: .error, channel: .process)
      throw .debuggee(error)
    }
  }
}

internal enum GDBEnvironmentPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              launch: inout Debuggee.Launch,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let value = try GDBPacketReader.string(payload)
    return try set(value, launch: &launch, writer: &writer)
  }

  internal static func raw(_ payload: borrowing Span<UInt8>,
                           launch: inout Debuggee.Launch,
                           writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let value = String(decoding: payload, as: UTF8.self)
    try set(value, launch: &launch, writer: &writer)
  }

  internal static func reset(_ payload: borrowing Span<UInt8>,
                             launch: inout Debuggee.Launch,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    launch.environment.removeAll(keepingCapacity: true)
    try writer.append("OK")
  }

  internal static func unset(_ payload: borrowing Span<UInt8>,
                             launch: inout Debuggee.Launch,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let name = try GDBPacketReader.string(payload)
    let entry = Debuggee.Environment(name: name, value: nil)
    guard entry.valid else {
      throw .malformed
    }
    if let index = launch.environment.firstIndex(where: { environment in
      Host.precedes(environment.name, name) == false &&
          Host.precedes(name, environment.name) == false
    }) {
      launch.environment[index] = entry
    } else {
      launch.environment.append(entry)
    }
    try writer.append("OK")
  }
}

private func set(_ value: String, launch: inout Debuggee.Launch,
                 writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  guard let separator = value.firstIndex(of: "=") else {
    throw .malformed
  }
  let name = String(value[..<separator])
  let start = value.index(after: separator)
  let entry = Debuggee.Environment(name: name, value: String(value[start...]))
  guard entry.valid else {
    throw .malformed
  }
  if let index = launch.environment.firstIndex(where: { environment in
    Host.precedes(environment.name, name) == false &&
        Host.precedes(name, environment.name) == false
  }) {
    launch.environment[index] = entry
  } else {
    launch.environment.append(entry)
  }
  try writer.append("OK")
}

internal enum GDBASLRPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              launch: inout Debuggee.Launch,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.count == 1 else {
      throw .malformed
    }
    switch payload[0] {
    case UInt8(ascii: "0"):
      launch.aslr = true
    case UInt8(ascii: "1"):
      launch.aslr = false
    default:
      throw .malformed
    }
    try writer.append("OK")
  }
}

internal enum GDBRunPacket {
  internal static func configure(_ payload: borrowing Span<UInt8>,
                                 launch: inout Debuggee.Launch)
      throws(GDBHandlerError) {
    launch.arguments.removeAll(keepingCapacity: true)
    var start = 0
    if payload.count > 0 {
      guard payload[0] == UInt8(ascii: ";") else {
        throw .malformed
      }
      start = 1
    }
    while start < payload.count {
      var end = start
      while end < payload.count, payload[end] != UInt8(ascii: ";") {
        end += 1
      }
      let argument =
          try GDBPacketReader.string(payload.extracting(start ..< end))
      launch.arguments.append(argument)
      start = end + 1
    }
    if launch.arguments.count > 0 {
      launch.executable = launch.arguments.removeFirst()
    }
    guard case .some = launch.executable else {
      throw .debuggee(.process)
    }
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try configure(payload, launch: &session.launch)
    do {
      _ = try session.spawn()
    } catch {
      throw .debuggee(error)
    }
  }
}
