// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBLibrariesRequest {
  internal let all: Bool
  internal let addresses: Array<UInt64>?
  internal let style: Debuggee.Image.Style

  internal init(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    guard reader.token(UInt8(ascii: "{")) else {
      throw .malformed
    }
    var all: Bool?
    var addresses: Array<UInt64>?
    var commands: Bool?
    var style: Debuggee.Image.Style?
    var first = true
    while reader.token(UInt8(ascii: "}")) == false {
      if first {
        first = false
      } else {
        guard reader.token(UInt8(ascii: ",")) else {
          throw .malformed
        }
      }
      let key = try reader.quoted()
      guard reader.token(UInt8(ascii: ":")) else {
        throw .malformed
      }
      switch () {
      case _ where reader.matches(key, value: "fetch_all_solibs"):
        guard all == nil else {
          throw .malformed
        }
        all = try reader.boolean()
      case _ where reader.matches(key, value: "solib_addresses"):
        guard addresses == nil else {
          throw .malformed
        }
        addresses = try reader.list()
      case _ where reader.matches(key, value: "report_load_commands"):
        guard commands == nil else {
          throw .malformed
        }
        commands = try reader.boolean()
      case _ where reader.matches(key, value: "information-level"):
        guard style == nil else {
          throw .malformed
        }
        style = try reader.detail()
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

extension DebugSession {
  internal borrowing func libraries(_ payload: borrowing Span<UInt8>,
                                    state: inout GDBRemoteSessionState,
                                    writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if payload.isEmpty {
      return try writer.append("OK")
    }
    let request = try GDBLibrariesRequest(payload)
    guard request.all || request.addresses != nil else {
      return try writer.append("OK")
    }
    let process = try state.selection.general.process(in: debuggee)
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
      let path = image.main ? launch.executable ?? image.path : image.path
      try writer.emit(image, path: path, style: request.style)
    }
    try writer.append("]}")
    state.modules = false
  }
}

extension GDBPacketWriter {
  fileprivate mutating func emit(_ image: borrowing Debuggee.Image,
                                 path: borrowing String,
                                 style: Debuggee.Image.Style)
      throws(GDBHandlerError) {
    try append("{\"load_address\":")
    try decimal(image.base.rawValue)
    if style == .address {
      return try append(UInt8(ascii: "}"))
    }
    try append(",\"pathname\":\"")
    try json(path)
    try append(UInt8(ascii: "\""))
    if let system = image.system, style == .full {
      try append(",\"min_version_os_name\":\"")
      try json(system)
      try append(UInt8(ascii: "\""))
    }
    if let description = image.description, style.described {
      try emit(description, style: style)
    }
    try append(UInt8(ascii: "}"))
  }
}

extension GDBPacketReader {
  fileprivate mutating func list() throws(GDBHandlerError) -> Array<UInt64> {
    guard token(UInt8(ascii: "[")) else {
      throw .malformed
    }
    var addresses = Array<UInt64>()
    if token(UInt8(ascii: "]")) {
      return addresses
    }
    while true {
      try addresses.append(decimal())
      if token(UInt8(ascii: "]")) {
        return addresses
      }
      guard token(UInt8(ascii: ",")) else {
        throw .malformed
      }
    }
  }

  fileprivate mutating func detail() throws(GDBHandlerError)
      -> Debuggee.Image.Style {
    if consume("\"address-only\"") {
      return .address
    }
    if consume("\"address-name\"") {
      return .name
    }
    if consume("\"address-name-uuid\"") {
      return .identifier
    }
    if consume("\"full\"") {
      return .full
    }
    throw .malformed
  }
}

extension Debuggee {
  @inline(__always)
  internal borrowing func library(_ payload: borrowing Span<UInt8>,
                                  state: borrowing GDBRemoteSessionState,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    let process = try state.selection.general.process(in: self)
    let address = try translate(process.address)
    try writer.hex(address.rawValue)
  }
}
