// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private let kPacketKeywords: Set<String> = [
  "associatedtype", "borrowing", "break", "case", "catch", "class", "consume",
  "consuming", "continue", "copy", "default", "defer", "deinit", "do", "else",
  "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func",
  "guard", "if", "import", "in", "init", "inout", "internal", "is", "let",
  "nil", "operator", "precedencegroup", "private", "protocol", "public",
  "repeat", "rethrows", "return", "self", "static", "struct", "subscript",
  "super", "switch", "throw", "throws", "true", "try", "typealias", "var",
  "where", "while", "as", "Any", "Self", "Type", "Protocol", "_",
  "unsupported", "transfer",
]

internal struct PacketDefinition: Decodable {
  internal let pattern: String
  internal let leaf: PacketLeaf
  internal let exact: Bool
  internal let availability: PacketAvailability
  internal let scope: PacketScope
  internal let request: PacketEncoding
  internal let response: PacketEncoding

  internal init(from decoder: Decoder) throws {
    let keys: Set<String> = [
      "pattern", "leaf", "exact", "feature", "compatibility", "scope",
      "request", "response",
    ]
    let values = try container(decoder, keys: keys)
    pattern = try values.decode(String.self, forKey: SchemaKey("pattern"))
    leaf = try PacketLeaf(values.decode(String.self, forKey: SchemaKey("leaf")))
    exact = try values.decodeIfPresent(Bool.self,
                                       forKey: SchemaKey("exact")) ?? true
    let feature =
        try values.decodeIfPresent(String.self, forKey: SchemaKey("feature"))
    let compatibility =
        try values.decodeIfPresent(String.self,
                                   forKey: SchemaKey("compatibility"))
    availability = try PacketAvailability(feature: feature,
                                          compatibility: compatibility)
    scope =
        try values.decodeIfPresent(PacketScope.self,
                                   forKey: SchemaKey("scope")) ?? .mode
    request =
        try values.decodeIfPresent(PacketEncoding.self,
                                   forKey: SchemaKey("request")) ?? .text
    response =
        try values.decodeIfPresent(PacketEncoding.self,
                                   forKey: SchemaKey("response")) ?? .text
  }
}

internal enum PacketScope: String, Decodable {
  case mode
  case remote
  case session
}

internal enum PacketEncoding: String, Decodable {
  case binary
  case text
}

internal enum PacketAvailability: UInt8 {
  case always
  case gdb
  case lldb
  case stopthreads
  case threadsuffix

  internal init(feature: String?, compatibility: String?)
      throws(DSXCodeGenError) {
    switch (feature, compatibility) {
    case (.some, .some):
      throw .schema("packet feature and compatibility cannot be combined")
    case (.some("stopthreads"), .none): self = .stopthreads
    case (.some("threadsuffix"), .none): self = .threadsuffix
    case (.some(let feature), .none):
      throw .schema("unsupported packet feature '\(feature)'")
    case (.none, .some("gdb")): self = .gdb
    case (.none, .some("lldb")): self = .lldb
    case (.none, .some(let mode)):
      throw .schema("unsupported compatibility mode '\(mode)'")
    case (.none, .none): self = .always
    }
  }
}

internal enum PacketLeaf: Hashable {
  case named(String)
  case transfer(String)

  internal init(_ value: String) throws(DSXCodeGenError) {
    if value.hasPrefix("transfer.") {
      let name = String(value.dropFirst("transfer.".count))
      switch name {
      case "features", "executable", "auxiliary", "libraries", "svr4",
           "threads", "osdata", "signal", "map":
        self = .transfer(name)
      default:
        throw .schema("unknown transfer object '\(name)'")
      }
    } else {
      guard identifier(value), kPacketKeywords.contains(value) == false else {
        throw .schema("invalid packet leaf '\(value)'")
      }
      self = .named(value)
    }
  }

  internal var expression: String {
    switch self {
    case .named(let name): ".\(name)"
    case .transfer(let name): ".transfer(.\(name))"
    }
  }
}
