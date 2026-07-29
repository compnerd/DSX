// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBProcessEnumeration: ~Copyable, Sendable {
  private var cursor: NativeProcessCursor
  private let filter: String?

  internal init(filter: String?) throws(Debuggee.Error) {
    cursor = try NativeProcessCursor()
    self.filter = filter
  }

  internal mutating func next() throws(Debuggee.Error)
      -> Debuggee.Process.Info? {
    while let info = try cursor.next() {
      if let filter, info.matches(filter) == false {
        continue
      }
      return info
    }
    return nil
  }
}

extension GDBPacketWriter {
  internal mutating func process(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    let process = try ProcessIdentifier(rawValue: UInt64(decimal: payload))
    let info = try translate(process.info)
    try emit(info, hex: false)
  }
}

extension GDBRemoteSessionState {
  internal mutating func processes(_ payload: borrowing Span<UInt8>,
                                   writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let filter = try reader.filter()
    enumeration.processes = try translate(GDBProcessEnumeration(filter: filter))
    return try processes(writer: &writer)
  }

  internal mutating func processes(writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard var processes = enumeration.processes.take() else {
      return try writer.error(GDBErrorCode.unavailable)
    }
    guard let info = try translate(processes.next()) else {
      return try writer.error(GDBErrorCode.unavailable)
    }
    enumeration.processes = consume processes
    return try writer.emit(info, hex: false)
  }
}

extension GDBPacketReader {
  fileprivate mutating func filter() throws(GDBHandlerError) -> String? {
    _ = consume(UInt8(ascii: ":"))
    while empty == false {
      let key = try field(UInt8(ascii: ":"))
      let value = try field(UInt8(ascii: ";"))
      if matches(key, value: "name") {
        return try String(hex: span(value))
      }
    }
    return nil
  }
}

extension GDBPacketWriter {
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
      case let (.some(system), _): try append(system.utf8Span.span)
      case let (.none, .some(system)): try append(system)
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
