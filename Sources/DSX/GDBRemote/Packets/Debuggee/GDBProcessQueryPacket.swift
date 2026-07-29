// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBProcessInfoPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let process = try ProcessIdentifier(rawValue: reader.decimal())
    guard reader.empty else {
      throw .malformed
    }
    let info = try translate(process.info)
    try write(info, hex: false, writer: &writer)
  }

  internal static func write(_ info: borrowing Debuggee.Process.Info, hex: Bool,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append("pid:")
    if hex {
      try writer.hex(info.process.rawValue)
    } else {
      try writer.decimal(info.process.rawValue)
    }
    try writer.append(UInt8(ascii: ";"))
    if let parent = info.parent {
      try writer.append(hex ? "parent-pid:" : "ppid:")
      if hex {
        try writer.hex(parent.rawValue)
      } else {
        try writer.decimal(parent.rawValue)
      }
      try writer.append(UInt8(ascii: ";"))
    }
    if hex {
      let metadata = Host.metadata
      if metadata.triple {
        try writer.triple(info.architecture)
      }
      if let cpu = info.cpu ?? metadata.cpu {
        try writer.field("cputype:", hex: cpu)
      }
      if let subtype = info.subtype ?? metadata.subtype {
        try writer.field("cpusubtype:", hex: subtype)
      }
      if let vendor = metadata.vendor {
        try writer.append("vendor:")
        try writer.append(vendor)
        try writer.append(UInt8(ascii: ";"))
      }
      try writer.append("ostype:")
      switch (info.system, metadata.system) {
      case (.some(let system), _):
        try writer.append(system.utf8Span.span)
      case (.none, .some(let system)):
        try writer.append(system)
      case (.none, .none):
        try writer.append(Host.system)
      }
      try writer.append(UInt8(ascii: ";"))
      try writer.append("endian:")
      try writer.append(ABI.endian.name)
      try writer.append(";ptrsize:")
      try writer.decimal(UInt64(ABI.width / 8))
      try writer.append(UInt8(ascii: ";"))
    } else {
      try writer.append("name:")
      try writer.encoded(info.name)
      try writer.append(UInt8(ascii: ";"))
      if info.arguments.count > 0 {
        try writer.append("args:")
        for index in info.arguments.indices {
          if index > 0 {
            try writer.append(UInt8(ascii: "-"))
          }
          try writer.encoded(info.arguments[index])
        }
        try writer.append(UInt8(ascii: ";"))
      }
      try writer.triple(info.architecture)
    }
  }
}

internal enum GDBProcessEnumerationPacket {
  internal static func first(_ payload: borrowing Span<UInt8>,
                             state: inout GDBRemoteSessionState,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    state.enumeration.processes = try translate(NativeProcessCursor())
    state.enumeration.filter = try name(payload)
    return try next(state: &state, writer: &writer)
  }

  internal static func next(state: inout GDBRemoteSessionState,
                            writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard var processes = state.enumeration.processes.take() else {
      return try writer.error(GDBErrorCode.unavailable)
    }
    while true {
      let info: Debuggee.Process.Info?
      do throws(Debuggee.Error) {
        info = try processes.next()
      } catch {
        continue
      }
      guard let info else {
        state.enumeration.processes = nil
        state.enumeration.filter = nil
        return try writer.error(GDBErrorCode.unavailable)
      }
      if let filter = state.enumeration.filter {
        guard info.matches(filter) else {
          continue
        }
      }
      state.enumeration.processes = consume processes
      return try GDBProcessInfoPacket.write(info, hex: false, writer: &writer)
    }
  }
}

private func name(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError)
    -> String? {
  guard !payload.isEmpty else {
    return nil
  }
  var reader = GDBPacketReader(payload.extracting(0...))
  _ = reader.consume(UInt8(ascii: ":"))
  while reader.empty == false {
    let key = try reader.field(UInt8(ascii: ":"))
    let value = try reader.field(UInt8(ascii: ";"))
    if reader.matches(key, value: "name") {
      return try GDBPacketReader.string(reader.span(value))
    }
  }
  return nil
}

extension GDBPacketWriter {
  internal mutating func encoded(_ value: borrowing String)
      throws(GDBHandlerError) {
    guard output.freeCapacity >= value.utf8.count * 2 else {
      throw .capacity
    }
    for byte in value.utf8 {
      try hex(byte)
    }
  }
}
