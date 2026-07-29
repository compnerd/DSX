// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBModulePacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              working: String?, writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request = try GDBModuleRequest(payload)
    let path = try request.resolve(working: working)
    let architecture = request.architecture
    let module =
        try translate(Debuggee.Module(path: path, architecture: architecture))
    guard request.compatible(module) else {
      throw .code(GDBErrorCode.invalid)
    }
    try writer.emit(module, request: request)
  }
}

extension GDBModuleRequest {
  internal init(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    let field = try reader.field(UInt8(ascii: ";"))
    let path = try GDBPacketReader.string(reader.span(field))
    let triple = try GDBPacketReader.string(reader.remaining())
    self.init(path: path, triple: triple)
  }

  internal func resolve(working: String?) throws(GDBHandlerError) -> String {
    try translate(NativeFileSystem.resolve(path, working: working))
  }

  internal func compatible(_ module: borrowing Debuggee.Module) -> Bool {
    guard let candidate = module.architecture else {
      return true
    }
    return ModuleArchitecture.matches(candidate, requested: architecture)
  }
}

internal enum GDBModulesPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              working: String?, writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    var reader = try GDBModulesReader(payload.extracting(0...))
    try writer.append(UInt8(ascii: "["))
    var comma = false
    while let request = try reader.next() {
      let module: Debuggee.Module
      do {
        let path = try request.resolve(working: working)
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
        try writer.append(UInt8(ascii: ","))
      }
      try writer.emit(json: module, request: request,
                      identifier: identity.value)
      comma = true
    }
    try writer.append(UInt8(ascii: "]"))
  }
}

internal struct GDBModulesReader: ~Escapable {
  private let payload: Span<UInt8>
  private var index: Int
  private var first: Bool

  @_lifetime(copy payload)
  internal init(_ payload: consuming Span<UInt8>) throws(GDBHandlerError) {
    self.payload = consume payload
    index = 0
    first = true
    whitespace()
    guard consume(UInt8(ascii: "[")) else {
      throw .malformed
    }
  }

  internal mutating func next() throws(GDBHandlerError) -> GDBModuleRequest? {
    while true {
      whitespace()
      if consume(UInt8(ascii: "]")) {
        whitespace()
        guard index == payload.count else {
          throw .malformed
        }
        return nil
      }
      if first {
        first = false
      } else {
        guard consume(UInt8(ascii: ",")) else {
          throw .malformed
        }
        whitespace()
      }
      let request = try object()
      if let request {
        return request
      }
    }
  }

  private mutating func object() throws(GDBHandlerError) -> GDBModuleRequest? {
    guard consume(UInt8(ascii: "{")) else {
      throw .malformed
    }
    var path: String?
    var triple: String?
    var first = true
    while true {
      whitespace()
      if consume(UInt8(ascii: "}")) {
        break
      }
      if first {
        first = false
      } else {
        guard consume(UInt8(ascii: ",")) else {
          throw .malformed
        }
        whitespace()
      }
      let key = try string()
      whitespace()
      guard consume(UInt8(ascii: ":")) else {
        throw .malformed
      }
      whitespace()
      let value = try string()
      switch field(key) {
      case .file: path = try decode(value)
      case .triple: triple = try decode(value)
      case nil: break
      }
    }
    guard let path, let triple else {
      return nil
    }
    return GDBModuleRequest(path: path, triple: triple)
  }

  private mutating func string() throws(GDBHandlerError) -> Range<Int> {
    guard consume(UInt8(ascii: "\"")) else {
      throw .malformed
    }
    let start = index
    while index < payload.count {
      let byte = payload[index]
      index += 1
      if byte == UInt8(ascii: "\"") {
        return start ..< index - 1
      }
      guard byte >= UInt8(ascii: " ") else {
        throw .malformed
      }
      guard byte == UInt8(ascii: "\\") else {
        continue
      }
      guard index < payload.count else {
        throw .malformed
      }
      let escape = payload[index]
      index += 1
      guard let _ = escaped(escape) else {
        throw .malformed
      }
    }
    throw .malformed
  }

  private func field(_ range: Range<Int>) -> GDBModuleField? {
    let reader = GDBPacketReader(payload.extracting(0...))
    if reader.matches(range, value: "file") {
      return .file
    }
    if reader.matches(range, value: "triple") {
      return .triple
    }
    return nil
  }

  private func decode(_ range: Range<Int>) throws(GDBHandlerError) -> String {
    let bytes = payload.extracting(range)
    var escape = false
    for index in 0 ..< bytes.count where bytes[index] == UInt8(ascii: "\\") {
      escape = true
      break
    }
    guard escape else {
      return String(decoding: bytes, as: UTF8.self)
    }
    let capacity = bytes.count
    let result = withUnsafeTemporaryAllocation(of: UInt8.self,
                                               capacity: capacity) { buffer in
      unescape(bytes, into: buffer)
    }
    return try result.get()
  }

  private mutating func consume(_ byte: UInt8) -> Bool {
    guard index < payload.count, payload[index] == byte else {
      return false
    }
    index += 1
    return true
  }

  private mutating func whitespace() {
    while index < payload.count {
      switch payload[index] {
      case UInt8(ascii: "\t"), UInt8(ascii: "\n"),
          UInt8(ascii: "\r"), UInt8(ascii: " "): index += 1
      default: return
      }
    }
  }
}

private func unescape(_ bytes: borrowing Span<UInt8>,
                      into buffer: UnsafeMutableBufferPointer<UInt8>)
    -> Result<String, GDBHandlerError> {
  var decoded = OutputSpan(buffer: buffer, initializedCount: 0)
  var index = 0
  while index < bytes.count {
    let byte = bytes[index]
    index += 1
    guard byte == UInt8(ascii: "\\") else {
      decoded.append(byte)
      continue
    }
    guard index < bytes.count, let escape = escaped(bytes[index]) else {
      return .failure(.malformed)
    }
    index += 1
    decoded.append(escape)
  }
  let value = String(decoding: decoded.span, as: UTF8.self)
  return .success(value)
}

private func escaped(_ byte: UInt8) -> UInt8? {
  switch byte {
  case UInt8(ascii: "\""), UInt8(ascii: "/"), UInt8(ascii: "\\"): byte
  case UInt8(ascii: "b"): 0x08
  case UInt8(ascii: "f"): 0x0c
  case UInt8(ascii: "n"): 0x0a
  case UInt8(ascii: "r"): 0x0d
  case UInt8(ascii: "t"): 0x09
  default: nil
  }
}

private enum GDBModuleField {
  case file
  case triple
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
  internal mutating func emit(_ module: Debuggee.Module,
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

  internal mutating func emit(json module: Debuggee.Module,
                              request: borrowing GDBModuleRequest,
                              identifier: String) throws(GDBHandlerError) {
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
