// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func host() throws(GDBHandlerError) {
    try triple(ABI.machine)
    try append("ptrsize:")
    try decimal(UInt64(ABI.width.bytes))
    try append(";endian:")
    try append(ABI.endian.name)
    try append(UInt8(ascii: ";"))
    let metadata = Host.metadata
    if let cpu = metadata.cpu {
      try field("cputype:", decimal: cpu)
    }
    if let subtype = metadata.subtype {
      try field("cpusubtype:", decimal: subtype)
    }
    if let addressing = metadata.addressing {
      try field("addressing_bits:", decimal: addressing)
    }
    if let vendor = metadata.vendor {
      try append("vendor:")
      try append(vendor)
      try append(UInt8(ascii: ";"))
    }
    if let system = metadata.system {
      try append("ostype:")
      try append(system)
      try append(UInt8(ascii: ";"))
    }
    if let version = Host.version {
      try append("os_version:")
      try append(version.utf8Span.span)
      try append(UInt8(ascii: ";"))
    }
    if let watchpoint = metadata.watchpoint {
      try append("watchpoint_exceptions_received:")
      try append(watchpoint)
      try append(UInt8(ascii: ";"))
    }
    if let kernel = Host.kernel {
      try append("os_kernel:")
      try encoded(kernel)
      try append(UInt8(ascii: ";"))
    }
  }
}

extension DebugSession {
  @inline(__always)
  internal mutating func info(_ payload: borrowing Span<UInt8>,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard !debuggee.processes.isEmpty else {
      throw .code(GDBErrorCode.process)
    }
    let process = try state.selection.general.process(in: debuggee)
    let info = try translate(info(process))
    try writer.emit(info, hex: true)
  }
}

extension DebugSession {
  internal borrowing func attached(_ payload: borrowing Span<UInt8>,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    if payload.count > 0 {
      var reader = GDBPacketReader(payload.extracting(0...))
      guard reader.consume(UInt8(ascii: ":")) else {
        throw .malformed
      }
      let process = try ProcessIdentifier(rawValue: reader.hex())
      guard reader.empty, debuggee.contains(process) else {
        throw .debuggee(.process)
      }
    }
    try writer.append(attached ? UInt8(ascii: "1") : UInt8(ascii: "0"))
    return .reply
  }
}

extension DebugSession {
  internal borrowing func success(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if failed {
      return try writer.append("Elaunch failed")
    }
    try writer.append("OK")
  }
}

extension GDBPacketWriter {
  internal mutating func version() throws(GDBHandlerError) {
    try append("name:DebugServerX;version:0.0.0;build_number:0;")
    try append("major_version:0;minor_version:0;")
  }
}

extension Debuggee.Launch {
  internal borrowing func directory(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard let directory = directory else {
      throw .unsupported
    }
    try writer.encoded(directory)
  }
}

extension GDBPacketWriter {
  internal mutating func symbol(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    guard payload.count == 0 || payload[0] == UInt8(ascii: ":") else {
      throw .malformed
    }
    try append("OK")
  }
}

extension GDBPacketWriter {
  internal mutating func triple(_ architecture: StaticString)
      throws(GDBHandlerError) {
    try append("triple:")
    try encoded(architecture)
    try suffix()
  }

  internal mutating func triple(_ architecture: borrowing String)
      throws(GDBHandlerError) {
    try append("triple:")
    try encoded(architecture)
    try suffix()
  }

  private mutating func suffix() throws(GDBHandlerError) {
    try encoded("-")
    let metadata = Host.metadata
    if let vendor = metadata.vendor {
      try encoded(vendor)
    } else {
      try encoded("unknown")
    }
    try encoded("-")
    if let system = metadata.system {
      try encoded(system)
    } else {
      try encoded(Host.platform)
    }
    if let environment = metadata.environment {
      try encoded("-")
      try encoded(environment)
    }
    try append(UInt8(ascii: ";"))
  }
}
