// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBHostInfoPacket {
  internal static func handle(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.triple(ABI.machine)
    try writer.append("ptrsize:")
    try writer.decimal(UInt64(ABI.width.bytes))
    try writer.append(";endian:")
    try writer.append(ABI.endian.name)
    try writer.append(UInt8(ascii: ";"))
    let metadata = Host.metadata
    if let cpu = metadata.cpu {
      try writer.field("cputype:", decimal: cpu)
    }
    if let subtype = metadata.subtype {
      try writer.field("cpusubtype:", decimal: subtype)
    }
    if let addressing = metadata.addressing {
      try writer.field("addressing_bits:", decimal: addressing)
    }
    if let vendor = metadata.vendor {
      try writer.append("vendor:")
      try writer.append(vendor)
      try writer.append(UInt8(ascii: ";"))
    }
    if let system = metadata.system {
      try writer.append("ostype:")
      try writer.append(system)
      try writer.append(UInt8(ascii: ";"))
    }
    if let version = Host.version {
      try writer.append("os_version:")
      try writer.append(version.utf8Span.span)
      try writer.append(UInt8(ascii: ";"))
    }
    if let watchpoint = metadata.watchpoint {
      try writer.append("watchpoint_exceptions_received:")
      try writer.append(watchpoint)
      try writer.append(UInt8(ascii: ";"))
    }
    if let kernel = Host.kernel {
      try writer.append("os_kernel:")
      try writer.encoded(kernel)
      try writer.append(UInt8(ascii: ";"))
    }
  }
}

internal enum GDBCurrentProcessInfoPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard !session.debuggee.processes.isEmpty else {
      throw .code(GDBErrorCode.process)
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    let info = try translate(session.info(process))
    try writer.emit(info, hex: true)
  }
}

internal enum GDBAttachedPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    if payload.count > 0 {
      var reader = GDBPacketReader(payload.extracting(0...))
      guard reader.consume(UInt8(ascii: ":")) else {
        throw .malformed
      }
      let process = try ProcessIdentifier(rawValue: reader.hex())
      guard reader.empty, session.debuggee.contains(process) else {
        throw .debuggee(.process)
      }
    }
    try writer.append(session.attached
        ? UInt8(ascii: "1") : UInt8(ascii: "0"))
    return .reply
  }
}

internal enum GDBLaunchSuccessPacket {
  internal static func handle(session: borrowing DebugSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if session.failed {
      return try writer.append("Elaunch failed")
    }
    try writer.append("OK")
  }
}

internal enum GDBServerVersionPacket {
  internal static func handle(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append("name:DebugServerX;version:0.0.0;build_number:0;")
    try writer.append("major_version:0;minor_version:0;")
  }
}

internal enum GDBGetWorkingDirectoryPacket {
  internal static func handle(launch: borrowing Debuggee.Launch,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard let working = launch.working else {
      throw .unsupported
    }
    try writer.encoded(working)
  }
}

internal enum GDBSymbolPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.count == 0 || payload[0] == UInt8(ascii: ":") else {
      throw .malformed
    }
    try writer.append("OK")
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

  internal mutating func encoded(_ value: StaticString)
      throws(GDBHandlerError) {
    guard output.freeCapacity >= value.utf8CodeUnitCount * 2 else {
      throw .capacity
    }
    value.withUTF8Buffer { buffer in
      for byte in buffer {
        output.append(GDBPacketWriter.hexadecimal(byte >> 4))
        output.append(GDBPacketWriter.hexadecimal(byte))
      }
    }
  }
}
