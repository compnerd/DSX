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
        try write(description, style: request.style, writer: &writer)
      }
      try writer.append(UInt8(ascii: "}"))
    }
    try writer.append("]}")
    state.modules = false
  }

  internal static func write(_ description: borrowing Debuggee.ImageDescription,
                             style: Debuggee.Image.Style = .full,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if style == .full {
      let header = description.header
      try writer.append(",\"mach_header\":{\"magic\":")
      try writer.decimal(UInt64(header.magic))
      try writer.append(",\"cputype\":")
      try writer.decimal(UInt64(header.cpu))
      try writer.append(",\"cpusubtype\":")
      try writer.decimal(UInt64(header.subtype))
      try writer.append(",\"filetype\":")
      try writer.decimal(UInt64(header.file))
      try writer.append(",\"flags\":")
      try writer.decimal(UInt64(header.flags))
      try writer.append(",\"sizeof_mh_and_loadcmds\":")
      try writer.decimal(UInt64(header.size))
      try writer.append("},\"segments\":[")
      for index in 0 ..< description.segments.count {
        if index > 0 {
          try writer.append(UInt8(ascii: ","))
        }
        let segment = description.segments[index]
        try writer.append("{\"name\":\"")
        try writer.json(segment.name)
        try writer.append("\",\"vmaddr\":")
        try writer.decimal(segment.address)
        try writer.append(",\"vmsize\":")
        try writer.decimal(segment.size)
        try writer.append(",\"fileoff\":")
        try writer.decimal(segment.offset)
        try writer.append(",\"filesize\":")
        try writer.decimal(segment.bytes)
        try writer.append(",\"maxprot\":")
        try writer.decimal(UInt64(segment.protection))
        try writer.append(UInt8(ascii: "}"))
      }
      try writer.append(UInt8(ascii: "]"))
    }
    try writer.append(",\"uuid\":\"")
    try writer.json(description.identifier)
    try writer.append(UInt8(ascii: "\""))
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
    try write(offsets, writer: &writer)
  }

  internal static func write(_ offsets: Debuggee.ImageOffsets,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    switch offsets {
    case .sections(let text, let data):
      try writer.append("Text=")
      try writer.hex(text)
      try writer.append(";Data=")
      try writer.hex(data)
      try writer.append(";Bss=")
      try writer.hex(data)
    case .segments(let text, let data):
      try writer.append("TextSeg=")
      try writer.hex(text.rawValue)
      if let data {
        try writer.append(";DataSeg=")
        try writer.hex(data.rawValue)
      }
    }
  }
}
