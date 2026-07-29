// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func emit(_ request: borrowing GDBModuleRequest,
                              directory: String?) throws(GDBHandlerError) {
    let path = try request.resolve(directory: directory)
    let module =
        try translate(Debuggee.Module(path: path,
                                      architecture: request.architecture))
    guard request.compatible(module) else {
      throw .code(GDBErrorCode.invalid)
    }
    try emit(module, request: request)
  }
}

extension GDBModuleRequest {
  internal init(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let field = try reader.field(UInt8(ascii: ";"))
    let path = try String(hex: reader.span(field))
    let triple = try String(hex: reader.remaining())
    self.init(path: path, triple: triple)
  }

  internal func resolve(directory: String?) throws(GDBHandlerError) -> String {
    try translate(NativeFileSystem.resolve(path, directory: directory))
  }

  internal func compatible(_ module: borrowing Debuggee.Module) -> Bool {
    guard let candidate = module.architecture else {
      return true
    }
    return candidate.matches(architecture: architecture)
  }
}

extension GDBPacketWriter {
  internal mutating func emit(_ modules: inout GDBModulesReader,
                              directory: String?) throws(GDBHandlerError) {
    try append(UInt8(ascii: "["))
    var comma = false
    while let request = try modules.next() {
      let module: Debuggee.Module
      do {
        let path = try request.resolve(directory: directory)
        module =
            try Debuggee.Module(path: path, architecture: request.architecture)
      } catch {
        continue
      }
      guard request.compatible(module) else {
        continue
      }
      guard let identity = module.identity else {
        continue
      }
      if comma {
        try append(UInt8(ascii: ","))
      }
      try emit(json: module, request: request, identifier: identity.value)
      comma = true
    }
    try append(UInt8(ascii: "]"))
  }
}

internal struct GDBModulesReader: ~Escapable {
  private var reader: GDBPacketReader
  private var first: Bool

  @_lifetime(copy payload)
  internal init(_ payload: consuming Span<UInt8>) throws(GDBHandlerError) {
    reader = GDBPacketReader(consume payload)
    first = true
    guard reader.token(UInt8(ascii: "[")) else {
      throw .malformed
    }
  }

  internal mutating func next() throws(GDBHandlerError) -> GDBModuleRequest? {
    while true {
      if reader.token(UInt8(ascii: "]")) {
        guard reader.empty else {
          throw .malformed
        }
        return nil
      }
      if first {
        first = false
      } else {
        guard reader.token(UInt8(ascii: ",")) else {
          throw .malformed
        }
      }
      let request = try GDBModuleRequest(&reader)
      if let request {
        return request
      }
    }
  }
}

extension GDBModuleRequest {
  fileprivate init?(_ reader: inout GDBPacketReader) throws(GDBHandlerError) {
    guard reader.token(UInt8(ascii: "{")) else {
      throw .malformed
    }
    var path: String?
    var triple: String?
    var first = true
    while true {
      if reader.token(UInt8(ascii: "}")) {
        break
      }
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
      let value = try reader.quoted()
      switch () {
      case () where reader.matches(key, value: "file"):
        path = try reader.json(value)
      case () where reader.matches(key, value: "triple"):
        triple = try reader.json(value)
      default:
        break
      }
    }
    guard let path, let triple else {
      return nil
    }
    guard path.utf8.contains(0) == false,
        triple.utf8.contains(0) == false else {
      throw .malformed
    }
    self.init(path: path, triple: triple)
  }
}

internal struct GDBModuleRequest: Sendable {
  internal let path: String
  internal let triple: String

  internal var architecture: String {
    let end = triple.firstIndex(of: "-") ?? triple.endIndex
    return String(triple[..<end])
  }

  internal func triple(_ architecture: String?) -> String {
    guard let architecture else {
      return triple
    }
    let end = triple.firstIndex(of: "-") ?? triple.endIndex
    return architecture + triple[end...]
  }
}

extension GDBPacketWriter {
  internal mutating func emit(_ module: borrowing Debuggee.Module,
                              request: borrowing GDBModuleRequest)
      throws(GDBHandlerError) {
    if let identity = module.identity {
      switch identity {
      case .digest: try append("md5:")
      case .unique: try append("uuid:")
      }
      try encoded(identity.value)
      try append(UInt8(ascii: ";"))
    }
    try append("triple:")
    try encoded(request.triple(module.architecture))
    try append(";file_path:")
    try encoded(module.path)
    try append(";file_offset:")
    try hex(module.base.rawValue)
    try append(";file_size:")
    try hex(module.size)
    try append(UInt8(ascii: ";"))
  }

  internal mutating func emit(json module: borrowing Debuggee.Module,
                              request: borrowing GDBModuleRequest,
                              identifier: borrowing String)
      throws(GDBHandlerError) {
    try append(UInt8(ascii: "{"))
    try member("file_path", value: module.path, comma: false)
    try number("file_offset", value: module.base.rawValue)
    try number("file_size", value: module.size)
    let triple = request.triple(module.architecture)
    try member("triple", value: triple, comma: true)
    try member("uuid", value: identifier, comma: true)
    try append(UInt8(ascii: "}"))
  }

  private mutating func member(_ key: StaticString, value: borrowing String,
                               comma: Bool) throws(GDBHandlerError) {
    if comma {
      try append(UInt8(ascii: ","))
    }
    try append(UInt8(ascii: "\""))
    try append(key)
    try append("\":\"")
    try json(value)
    try append(UInt8(ascii: "\""))
  }

  private mutating func number(_ key: StaticString, value: UInt64)
      throws(GDBHandlerError) {
    try append(",\"")
    try append(key)
    try append("\":")
    try decimal(value)
  }
}
