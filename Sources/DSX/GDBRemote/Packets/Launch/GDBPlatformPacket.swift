// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension PlatformSession {
  internal mutating func launch(_ payload: borrowing Span<UInt8>,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request = try GDBLaunchRequest(payload)
    let child: HostProcess.Information
    do {
      child = try launch(host: request.host, port: request.port)
    } catch {
      error.log("failed to launch GDB server", channel: .system)
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

extension PlatformSession {
  internal borrowing func query(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard let child = servers.last else {
      throw .code(GDBErrorCode.unavailable)
    }
    try writer.emit(query: child)
  }
}

extension GDBDirectoryRequest {
  internal borrowing func permissions(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard !path.isEmpty else {
      throw .malformed
    }
    try translate(NativeFileSystem.permissions(path, mode: mode))
    try writer.append("F0")
  }
}

extension PlatformSession {
  @inline(__always)
  internal borrowing func info(_ payload: borrowing Span<UInt8>,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard let process else {
      throw .code(GDBErrorCode.process)
    }
    let info = try translate(process.info)
    try writer.emit(info, hex: true)
  }
}

extension GDBShellRequest {
  internal borrowing func execute(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append("F,00000000,00000000,")
    let status =
        try translate(Host.execute(command, directory: directory,
                                   timeout: timeout, into: &writer.output))
    writer.patch(status)
  }
}

extension GDBPacketWriter {
  internal mutating func patch(_ status: Debuggee.ProgramStatus) {
    switch status {
    case .completed(.exited(let code)):
      fixed(UInt32(bitPattern: code), offset: 2)
      fixed(0, offset: 11)
    case .completed(.signalled(let signal)):
      fixed(UInt32.max, offset: 2)
      fixed(UInt32(bitPattern: signal), offset: 11)
    case .timeout:
      fixed(UInt32.max, offset: 2)
      fixed(0, offset: 11)
    }
  }
}

extension GDBShellRequest {
  internal init(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let field = try reader.field(UInt8(ascii: ","))
    let command = try String(hex: reader.span(field))
    let timeout = try reader.hex()
    let separated = reader.consume(UInt8(ascii: ","))
    guard separated || reader.empty else {
      throw .malformed
    }
    let directory: String? = if separated {
      try String(hex: reader.remaining())
    } else {
      nil
    }
    self.init(command: command, directory: directory, timeout: timeout)
  }
}

internal struct GDBShellRequest: Sendable {
  internal let command: String
  internal let directory: String?
  internal let timeout: UInt64
}

extension GDBDirectoryRequest {
  internal borrowing func create(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try translate(NativeFileSystem.create(path, mode: mode))
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
    let path = try String(hex: reader.remaining())
    self.init(path: path, mode: UInt32(mode))
  }
}

internal struct GDBDirectoryRequest: Sendable {
  internal let path: String
  internal let mode: UInt32
}

extension GDBPacketWriter {
  internal mutating func completion(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let directories = try reader.decimal()
    guard directories <= 1, reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
    let path = try String(hex: reader.remaining())
    let directory = directories == 1
    let completions =
        try translate(NativeFileSystem.complete(path, directories: directory))
    try append("M")
    for index in completions.indices {
      if index > completions.startIndex {
        try append(UInt8(ascii: ","))
      }
      try encoded(completions[index])
    }
  }
}

extension PlatformSession {
  internal mutating func remove(_ payload: borrowing Span<UInt8>,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try ProcessIdentifier(rawValue: UInt64(decimal: payload))
    try translate(remove(process))
    try writer.append("OK")
  }
}

extension GDBPacketWriter {
  private mutating func fixed(_ value: UInt32, offset: Int) {
    var shift = 28
    for index in 0 ..< 8 {
      let digit = UInt8(truncatingIfNeeded: value >> shift)
      output[offset + index] = digit.hexadecimal
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
