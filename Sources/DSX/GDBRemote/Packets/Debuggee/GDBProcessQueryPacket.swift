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
    try writer.emit(info, hex: false)
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
      return try writer.emit(info, hex: false)
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

  internal mutating func emit(_ info: borrowing Debuggee.Process.Info,
                              hex hexadecimal: Bool) throws(GDBHandlerError) {
    try append("pid:")
    if hexadecimal {
      try hex(info.process.rawValue)
    } else {
      try decimal(info.process.rawValue)
    }
    try append(UInt8(ascii: ";"))
    if let parent = info.parent {
      try append(hexadecimal ? "parent-pid:" : "ppid:")
      if hexadecimal {
        try hex(parent.rawValue)
      } else {
        try decimal(parent.rawValue)
      }
      try append(UInt8(ascii: ";"))
    }
    if hexadecimal {
      let metadata = Host.metadata
      if metadata.triple {
        try triple(info.architecture)
      }
      if let cpu = info.cpu ?? metadata.cpu {
        try field("cputype:", hex: cpu)
      }
      if let subtype = info.subtype ?? metadata.subtype {
        try field("cpusubtype:", hex: subtype)
      }
      if let vendor = metadata.vendor {
        try append("vendor:")
        try append(vendor)
        try append(UInt8(ascii: ";"))
      }
      try append("ostype:")
      switch (info.system, metadata.system) {
      case (.some(let system), _): try append(system.utf8Span.span)
      case (.none, .some(let system)): try append(system)
      case (.none, .none): try append(Host.system)
      }
      try append(UInt8(ascii: ";"))
      try append("endian:")
      try append(ABI.endian.name)
      try append(";ptrsize:")
      try decimal(UInt64(ABI.width.bytes))
      try append(UInt8(ascii: ";"))
    } else {
      try append("name:")
      try encoded(info.name)
      try append(UInt8(ascii: ";"))
      if info.arguments.count > 0 {
        try append("args:")
        for index in info.arguments.indices {
          if index > 0 {
            try append(UInt8(ascii: "-"))
          }
          try encoded(info.arguments[index])
        }
        try append(UInt8(ascii: ";"))
      }
      try triple(info.architecture)
    }
  }
}
