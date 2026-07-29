// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBModulePacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              working: String?, writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let request = try GDBModulePacket.parse(payload)
    let path = try resolve(request.path, working: working)
    let architecture = request.architecture
    let module =
        try translate(Debuggee.Module(path: path, architecture: architecture))
    guard request.compatible(module) else {
      throw .code(GDBErrorCode.invalid)
    }
    try GDBModulePacket.write(request, module: module, writer: &writer)
  }

  internal static func parse(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) -> GDBModuleRequest {
    var reader = GDBPacketReader(payload.extracting(0...))
    let field = try reader.field(UInt8(ascii: ";"))
    let path = try GDBPacketReader.string(reader.span(field))
    let triple = try GDBPacketReader.string(reader.remaining())
    return GDBModuleRequest(path: path, triple: triple)
  }

  internal static func write(_ request: GDBModuleRequest,
                             module: Debuggee.Module,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if let identity = module.identity {
      switch identity {
      case .digest: try writer.append("md5:")
      case .unique: try writer.append("uuid:")
      }
      try writer.encoded(identity.value)
      try writer.append(UInt8(ascii: ";"))
    }
    try writer.append("triple:")
    try writer.encoded(request.triple(module.architecture))
    try writer.append(";file_path:")
    try writer.encoded(module.path)
    try writer.append(";file_offset:")
    try writer.hex(module.base.rawValue)
    try writer.append(";file_size:")
    try writer.hex(module.size)
    try writer.append(UInt8(ascii: ";"))
  }

  internal static func resolve(_ path: String, working: String?)
      throws(GDBHandlerError) -> String {
    try translate(NativeFileSystem.resolve(path, working: working))
  }
}

extension GDBModuleRequest {
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
        let path = try GDBModulePacket.resolve(request.path, working: working)
        module = try Debuggee.Module(path: path,
                                     architecture: request.architecture)
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
      try write(request, module: module, identifier: identity.value,
                writer: &writer)
      comma = true
    }
    try writer.append(UInt8(ascii: "]"))
  }

  internal static func write(_ request: GDBModuleRequest,
                             module: Debuggee.Module, identifier: String,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append(UInt8(ascii: "{"))
    try member("file_path", value: module.path, comma: false, writer: &writer)
    try number("file_offset", value: module.base.rawValue, writer: &writer)
    try number("file_size", value: module.size, writer: &writer)
    let triple = request.triple(module.architecture)
    try member("triple", value: triple, comma: true, writer: &writer)
    try member("uuid", value: identifier, comma: true, writer: &writer)
    try writer.append(UInt8(ascii: "}"))
  }
}

private func member(_ key: StaticString, value: borrowing String, comma: Bool,
                    writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  if comma {
    try writer.append(UInt8(ascii: ","))
  }
  try writer.append(UInt8(ascii: "\""))
  try writer.append(key)
  try writer.append("\":\"")
  try writer.json(value)
  try writer.append(UInt8(ascii: "\""))
}

private func number(_ key: StaticString, value: UInt64,
                    writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  try writer.append(",\"")
  try writer.append(key)
  try writer.append("\":")
  try writer.decimal(value)
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
