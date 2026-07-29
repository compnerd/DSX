// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBLaunchServerPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              server: inout PlatformSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request = try GDBLaunchRequest(payload)
    let child: HostProcess.Information
    do {
      child = try server.launch(host: request.host, port: request.port)
    } catch {
      DSX.log("failed to launch GDB server: \(error)", level: .error,
              channel: .system)
      throw .debuggee(error)
    }
    try writer.emit(launch: child)
  }
}

extension GDBLaunchRequest {
  internal init(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    var host: String?
    var port: UInt16?
    if reader.count > 0 {
      guard reader.consume(UInt8(ascii: ";")) else {
        throw .malformed
      }
    }
    while reader.count > 0 {
      let name = try reader.field(UInt8(ascii: ":"))
      let value = try reader.field(UInt8(ascii: ";"))
      if reader.matches(name, value: "host") {
        host = String(decoding: reader.span(value), as: UTF8.self)
        continue
      }
      guard reader.matches(name, value: "port") else {
        throw .unsupported
      }
      var number = GDBPacketReader(reader.span(value))
      let parsed = try number.decimal()
      guard number.empty, parsed <= UInt64(UInt16.max) else {
        throw .malformed
      }
      port = UInt16(parsed)
    }
    self.init(host: host, port: port)
  }
}

internal struct GDBLaunchRequest: Sendable {
  internal let host: String?
  internal let port: UInt16?
}

internal enum GDBQueryServerPacket {
  internal static func handle(server: borrowing PlatformSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard let child = server.servers.last else {
      throw .code(GDBErrorCode.unavailable)
    }
    try writer.emit(query: child)
  }
}

internal enum GDBPlatformArgumentsPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              server: inout PlatformSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    _ = try GDBArgumentsPacket.handle(payload, launch: &server.launch,
                                      writer: &writer)
    _ = try translate(server.launch(server.launch))
  }
}

internal enum GDBPlatformRunPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              server: inout PlatformSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try GDBRunPacket.configure(payload, launch: &server.launch)
    _ = try translate(server.launch(server.launch))
    try writer.append("OK")
  }
}

internal enum GDBPlatformPermissionsPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              server: inout PlatformSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request = try GDBDirectoryRequest(payload)
    guard !request.path.isEmpty else {
      throw .malformed
    }
    try translate(NativeFileSystem.permissions(request.path,
                                               mode: request.mode))
    try writer.append("F0")
  }
}

internal enum GDBPlatformProcessInfoPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              server: inout PlatformSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard let child = server.servers.last else {
      throw .code(GDBErrorCode.process)
    }
    let info = try translate(child.process.info)
    try writer.emit(info, hex: true)
  }
}

internal enum GDBPlatformShellPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request = try GDBShellRequest(payload)
    try writer.append("F,00000000,00000000,")
    let working = request.working
    let status =
        try translate(Host.execute(request.command, directory: working,
                                   timeout: request.timeout,
                                   into: &writer.output))
    write(status, writer: &writer)
  }

  internal static func write(_ status: Debuggee.ProgramStatus,
                             writer: inout GDBPacketWriter) {
    switch status {
    case .completed(.exited(let code)):
      writer.fixed(UInt32(bitPattern: code), offset: 2)
      writer.fixed(0, offset: 11)
    case .completed(.signalled(let signal)):
      writer.fixed(UInt32.max, offset: 2)
      writer.fixed(UInt32(bitPattern: signal), offset: 11)
    case .timeout:
      writer.fixed(UInt32.max, offset: 2)
      writer.fixed(0, offset: 11)
    }
  }
}

extension GDBShellRequest {
  internal init(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let field = try reader.field(UInt8(ascii: ","))
    let command = try GDBPacketReader.string(reader.span(field))
    let timeout = try reader.hex()
    let separated = reader.consume(UInt8(ascii: ","))
    guard separated || reader.empty else {
      throw .malformed
    }
    let directory: String? = if separated {
      try GDBPacketReader.string(reader.remaining())
    } else {
      nil
    }
    self.init(command: command, working: directory, timeout: timeout)
  }
}

internal struct GDBShellRequest: Sendable {
  internal let command: String
  internal let working: String?
  internal let timeout: UInt64
}

internal enum GDBPlatformDirectoryPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              server: inout PlatformSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request = try GDBDirectoryRequest(payload)
    try translate(NativeFileSystem.create(request.path, mode: request.mode))
    try writer.append("F0")
  }
}

extension GDBDirectoryRequest {
  internal init(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let mode = try reader.hex()
    guard reader.consume(UInt8(ascii: ",")), mode <= UInt64(UInt32.max) else {
      throw .malformed
    }
    let path = try GDBPacketReader.string(reader.remaining())
    self.init(path: path, mode: UInt32(mode))
  }
}

internal struct GDBDirectoryRequest: Sendable {
  internal let path: String
  internal let mode: UInt32
}

internal enum GDBPathCompletionPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let directories = try reader.decimal()
    guard directories <= 1, reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let path = try GDBPacketReader.string(reader.remaining())
    let directory = directories == 1
    let completions =
        try translate(NativeFileSystem.complete(path, directories: directory))
    try writer.append("M")
    for index in completions.indices {
      if index > completions.startIndex {
        try writer.append(UInt8(ascii: ","))
      }
      try writer.encoded(completions[index])
    }
  }
}

internal enum GDBPlatformUserPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let identifier = try GDBPlatformIdentity.parse(payload)
    let name = try translate(Host.user(identifier))
    try writer.encoded(name)
  }
}

internal enum GDBPlatformGroupPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let identifier = try GDBPlatformIdentity.parse(payload)
    let name = try translate(Host.group(identifier))
    try writer.encoded(name)
  }
}

internal enum GDBKillServerPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              server: inout PlatformSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try parse(payload)
    try translate(server.remove(process))
    try writer.append("OK")
  }

  internal static func parse(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) -> ProcessIdentifier {
    var reader = GDBPacketReader(payload.extracting(0...))
    let identifier = try reader.decimal()
    guard reader.empty else {
      throw .malformed
    }
    return ProcessIdentifier(rawValue: identifier)
  }
}

internal enum GDBPlatformIdentity {
  internal static func parse(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) -> UInt64 {
    var reader = GDBPacketReader(payload.extracting(0...))
    let identifier = try reader.decimal()
    guard reader.empty else {
      throw .malformed
    }
    return identifier
  }
}

extension GDBPacketWriter {
  fileprivate mutating func fixed(_ value: UInt32, offset: Int) {
    var shift = 28
    for index in 0 ..< 8 {
      let digit = UInt8(truncatingIfNeeded: value >> shift)
      output[offset + index] = GDBPacketWriter.hexadecimal(digit)
      shift -= 4
    }
  }

  internal mutating func emit(launch child: HostProcess.Information)
      throws(GDBHandlerError) {
    try append("pid:")
    try decimal(child.process.rawValue)
    try append(";port:")
    try decimal(UInt64(child.port))
    try append(UInt8(ascii: ";"))
  }

  internal mutating func emit(query child: HostProcess.Information)
      throws(GDBHandlerError) {
    try append("[{\"port\":")
    try decimal(UInt64(child.port))
    try append("}]")
  }
}
