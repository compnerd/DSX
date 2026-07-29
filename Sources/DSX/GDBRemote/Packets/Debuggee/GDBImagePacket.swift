// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBLibrariesPacket {
  internal struct Request {
    internal let all: Bool
    internal let addresses: Array<UInt64>?
    internal let style: Debuggee.Image.Style

    internal init(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
      var reader = GDBPacketReader(payload.extracting(0...))
      guard reader.consume(UInt8(ascii: "{")) else {
        throw .malformed
      }
      var all: Bool?
      var addresses: Array<UInt64>?
      var commands: Bool?
      var style: Debuggee.Image.Style?
      var first = true
      while reader.consume(UInt8(ascii: "}")) == false {
        if first {
          first = false
        } else {
          guard reader.consume(UInt8(ascii: ",")) else {
            throw .malformed
          }
        }
        switch () {
        case _ where reader.consume("\"fetch_all_solibs\":"):
          guard all == nil else {
            throw .malformed
          }
          all = try reader.boolean()
        case _ where reader.consume("\"solib_addresses\":"):
          guard addresses == nil else {
            throw .malformed
          }
          addresses = try list(&reader)
        case _ where reader.consume("\"report_load_commands\":"):
          guard commands == nil else {
            throw .malformed
          }
          commands = try reader.boolean()
        case _ where reader.consume("\"information-level\":"):
          guard style == nil else {
            throw .malformed
          }
          style = try detail(&reader)
        default:
          throw .malformed
        }
      }
      guard reader.empty else {
        throw .malformed
      }
      self.all = all ?? false
      self.addresses = addresses
      self.style = style ?? commands.map { $0 ? .full : .address } ?? .full
    }
  }

  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if payload.isEmpty {
      return try writer.append("OK")
    }
    let request = try Request(payload)
    guard request.all || request.addresses != nil else {
      return try writer.append("OK")
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    let images = if let addresses = request.addresses {
      try translate(process.images(addresses.span, style: request.style))
    } else {
      try translate(process.images(request.style))
    }
    try writer.append("{\"images\":[")
    for index in 0 ..< images.count {
      if index > 0 {
        try writer.append(UInt8(ascii: ","))
      }
      let image = images[index]
      let path = if image.main {
        session.launch.executable ?? image.path
      } else {
        image.path
      }
      try writer.append("{\"load_address\":")
      try writer.decimal(image.base.rawValue)
      if request.style == .address {
        try writer.append(UInt8(ascii: "}"))
        continue
      }
      try writer.append(",\"pathname\":\"")
      try writer.json(path)
      try writer.append(UInt8(ascii: "\""))
      if let system = image.system, request.style == .full {
        try writer.append(",\"min_version_os_name\":\"")
        try writer.json(system)
        try writer.append(UInt8(ascii: "\""))
      }
      if let description = image.description, request.style.described {
        try writer.emit(description, style: request.style)
      }
      try writer.append(UInt8(ascii: "}"))
    }
    try writer.append("]}")
    state.modules = false
  }
}

private func list(_ reader: inout GDBPacketReader) throws(GDBHandlerError)
    -> Array<UInt64> {
  guard reader.consume(UInt8(ascii: "[")) else {
    throw .malformed
  }
  var addresses = Array<UInt64>()
  if reader.consume(UInt8(ascii: "]")) {
    return addresses
  }
  while true {
    try addresses.append(reader.decimal())
    if reader.consume(UInt8(ascii: "]")) {
      return addresses
    }
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
  }
}

private func detail(_ reader: inout GDBPacketReader) throws(GDBHandlerError)
    -> Debuggee.Image.Style {
  if reader.consume("\"address-only\"") {
    return .address
  }
  if reader.consume("\"address-name\"") {
    return .name
  }
  if reader.consume("\"address-name-uuid\"") {
    return .identifier
  }
  if reader.consume("\"full\"") {
    return .full
  }
  throw .malformed
}

extension GDBPacketReader {
  fileprivate mutating func boolean() throws(GDBHandlerError) -> Bool {
    if consume("true") {
      return true
    }
    guard consume("false") else {
      throw .malformed
    }
    return false
  }
}

internal enum GDBSharedLibraryPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: borrowing DebugSession,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    let address = try translate(process.address)
    try writer.hex(address.rawValue)
  }
}

internal enum GDBSharedCachePacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: borrowing DebugSession,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    guard payload.isEmpty || reader.consume("{}") && reader.empty else {
      throw .malformed
    }
    if payload.isEmpty {
      return try writer.append("OK")
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    let cache = try translate(process.cache)
    try writer.append("{\"shared_cache_base_address\":")
    try writer.decimal(cache.base.rawValue)
    try writer.append(",\"shared_cache_uuid\":\"")
    try writer.json(cache.identifier)
    try writer.append("\",\"no_shared_cache\":")
    try writer.append(cache.absent ? "true" : "false")
    try writer.append(",\"shared_cache_private_cache\":")
    try writer.append(cache.isolated ? "true" : "false")
    if let path = cache.path {
      try writer.append(",\"shared_cache_path\":\"")
      try writer.json(path)
      try writer.append(UInt8(ascii: "\""))
    }
    try writer.append(UInt8(ascii: "}"))
  }
}

internal enum GDBOffsetsPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: borrowing GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    let image = try translate(session.image(process))
    let offsets = try translate(image.offsets)
    try writer.emit(offsets)
  }
}

extension GDBPacketWriter {
  internal mutating func emit(_ image: borrowing Debuggee.ImageDescription,
                              style: Debuggee.Image.Style = .full)
      throws(GDBHandlerError) {
    if style == .full {
      let header = image.header
      try append(",\"mach_header\":{\"magic\":")
      try decimal(UInt64(header.magic))
      try append(",\"cputype\":")
      try decimal(UInt64(header.cpu))
      try append(",\"cpusubtype\":")
      try decimal(UInt64(header.subtype))
      try append(",\"filetype\":")
      try decimal(UInt64(header.file))
      try append(",\"flags\":")
      try decimal(UInt64(header.flags))
      try append(",\"sizeof_mh_and_loadcmds\":")
      try decimal(UInt64(header.size))
      try append("},\"segments\":[")
      for index in 0 ..< image.segments.count {
        if index > 0 {
          try append(UInt8(ascii: ","))
        }
        let segment = image.segments[index]
        try append("{\"name\":\"")
        try json(segment.name)
        try append("\",\"vmaddr\":")
        try decimal(segment.address)
        try append(",\"vmsize\":")
        try decimal(segment.size)
        try append(",\"fileoff\":")
        try decimal(segment.offset)
        try append(",\"filesize\":")
        try decimal(segment.bytes)
        try append(",\"maxprot\":")
        try decimal(UInt64(segment.protection))
        try append(UInt8(ascii: "}"))
      }
      try append(UInt8(ascii: "]"))
    }
    try append(",\"uuid\":\"")
    try json(image.identifier)
    try append(UInt8(ascii: "\""))
  }

  internal mutating func emit(_ offsets: Debuggee.ImageOffsets)
      throws(GDBHandlerError) {
    switch offsets {
    case .sections(let text, let data):
      try append("Text=")
      try hex(text)
      try append(";Data=")
      try hex(data)
      try append(";Bss=")
      try hex(data)
    case .segments(let text, let data):
      try append("TextSeg=")
      try hex(text.rawValue)
      if let data {
        try append(";DataSeg=")
        try hex(data.rawValue)
      }
    }
  }
}
