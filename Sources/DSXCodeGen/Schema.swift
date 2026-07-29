// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

import Yams

internal enum DSXCodeGenError:
    Error, Equatable, Sendable, CustomStringConvertible {
  case argument(String)
  case input(String)
  case output(String)
  case schema(String)

  internal var description: String {
    switch self {
    case .argument(let message), .schema(let message):
      message
    case .input(let path):
      "unable to read '\(path)'"
    case .output(let path):
      "unable to write '\(path)'"
    }
  }
}

internal struct SchemaKey: CodingKey, Hashable {
  internal let stringValue: String
  internal let intValue: Int?

  internal init(_ value: String) {
    stringValue = value
    intValue = nil
  }

  internal init?(stringValue: String) {
    self.init(stringValue)
  }

  internal init?(intValue: Int) {
    stringValue = String(intValue)
    self.intValue = intValue
  }
}

internal func container(_ decoder: Decoder, keys: Set<String>) throws
    -> KeyedDecodingContainer<SchemaKey> {
  let values = try decoder.container(keyedBy: SchemaKey.self)
  for key in values.allKeys {
    guard keys.contains(key.stringValue) else {
      throw DSXCodeGenError.schema("unknown field '\(key.stringValue)'")
    }
  }
  return values
}

internal enum ProfileLayout: String, Decodable {
  case fixed
  case scalable
}

internal enum RegisterPlatform: String, Decodable, Hashable {
  case android
  case apple
  case linux
}

internal struct RegisterSetDefinition: Decodable {
  internal let id: UInt16
  internal let name: String
  internal let title: String
  internal let platforms: Array<RegisterPlatform>

  internal init(from decoder: Decoder) throws {
    let values =
        try container(decoder, keys: ["id", "name", "title", "platforms"])
    id = try values.decode(UInt16.self, forKey: SchemaKey("id"))
    name = try values.decode(String.self, forKey: SchemaKey("name"))
    title = try values.decode(String.self, forKey: SchemaKey("title"))
    platforms =
        try values.decodeIfPresent(Array<RegisterPlatform>.self,
                                   forKey: SchemaKey("platforms")) ?? []
  }
}

internal struct RegisterFeatureDefinition: Decodable {
  internal let id: UInt16
  internal let name: String
  internal let includes: Array<String>
  internal let types: Array<RegisterTypeDefinition>
  internal let platforms: Array<RegisterPlatform>

  internal init(from decoder: Decoder) throws {
    let values =
        try container(decoder,
                      keys: ["id", "name", "includes", "types", "platforms"])
    id = try values.decode(UInt16.self, forKey: SchemaKey("id"))
    name = try values.decode(String.self, forKey: SchemaKey("name"))
    includes =
        try values.decode(Array<String>.self, forKey: SchemaKey("includes"))
    types =
        try values.decode(Array<RegisterTypeDefinition>.self,
                          forKey: SchemaKey("types"))
    platforms =
        try values.decodeIfPresent(Array<RegisterPlatform>.self,
                                   forKey: SchemaKey("platforms")) ?? []
  }
}

internal struct RegisterFieldDefinition: Decodable {
  internal let name: String
  internal let start: Int
  internal let end: Int
  internal let type: String?

  internal init(from decoder: Decoder) throws {
    let values = try container(decoder, keys: ["name", "start", "end", "type"])
    name = try values.decode(String.self, forKey: SchemaKey("name"))
    start = try values.decode(Int.self, forKey: SchemaKey("start"))
    end = try values.decode(Int.self, forKey: SchemaKey("end"))
    type = try values.decodeIfPresent(String.self, forKey: SchemaKey("type"))
  }
}

internal struct RegisterTypeDefinition: Decodable {
  internal let name: String
  internal let kind: RegisterTypeKind
  internal let bits: Int?
  internal let element: String?
  internal let count: Int?
  internal let fields: Array<RegisterFieldDefinition>

  internal init(from decoder: Decoder) throws {
    let keys: Set<String> = [
      "name", "kind", "bits", "element", "count", "fields",
    ]
    let values = try container(decoder, keys: keys)
    name = try values.decode(String.self, forKey: SchemaKey("name"))
    kind = try values.decode(RegisterTypeKind.self, forKey: SchemaKey("kind"))
    bits = try values.decodeIfPresent(Int.self, forKey: SchemaKey("bits"))
    element =
        try values.decodeIfPresent(String.self, forKey: SchemaKey("element"))
    count = try values.decodeIfPresent(Int.self, forKey: SchemaKey("count"))
    fields =
        try values.decode(Array<RegisterFieldDefinition>.self,
                          forKey: SchemaKey("fields"))
  }
}

internal struct RegisterNumberDefinition: Decodable {
  internal let gdb: Int?
  internal let lldb: Int?
  internal let dwarf: Int?
  internal let ehframe: Int?

  internal init(from decoder: Decoder) throws {
    let values =
        try container(decoder, keys: ["gdb", "lldb", "dwarf", "ehframe"])
    gdb = try values.decodeIfPresent(Int.self, forKey: SchemaKey("gdb"))
    lldb = try values.decodeIfPresent(Int.self, forKey: SchemaKey("lldb"))
    dwarf = try values.decodeIfPresent(Int.self, forKey: SchemaKey("dwarf"))
    ehframe = try values.decodeIfPresent(Int.self, forKey: SchemaKey("ehframe"))
  }
}

internal struct RegisterRelationDefinition: Decodable {
  internal let containers: Array<String>
  internal let invalidates: Array<String>

  internal init(from decoder: Decoder) throws {
    let values = try container(decoder, keys: ["containers", "invalidates"])
    containers =
        try values.decode(Array<String>.self, forKey: SchemaKey("containers"))
    invalidates =
        try values.decode(Array<String>.self, forKey: SchemaKey("invalidates"))
  }
}

internal struct RegisterDefinition: Decodable {
  internal let id: UInt32
  internal let name: String
  internal let alternate: String?
  internal let role: RegisterRole?
  internal let bits: Int
  internal let offset: Int
  internal let set: String
  internal let encoding: RegisterEncoding
  internal let format: RegisterFormat
  internal let numbers: RegisterNumberDefinition
  internal let relations: RegisterRelationDefinition
  internal let feature: String
  internal let type: String?
  internal let platforms: Array<RegisterPlatform>

  internal init(from decoder: Decoder) throws {
    let keys: Set<String> = [
      "id", "name", "alternate", "role", "bits", "offset", "set",
      "encoding", "format", "numbers", "relations", "feature", "type",
      "platforms",
    ]
    let values = try container(decoder, keys: keys)
    id = try values.decode(UInt32.self, forKey: SchemaKey("id"))
    name = try values.decode(String.self, forKey: SchemaKey("name"))
    alternate =
        try values.decodeIfPresent(String.self, forKey: SchemaKey("alternate"))
    role =
        try values.decodeIfPresent(RegisterRole.self, forKey: SchemaKey("role"))
    bits = try values.decode(Int.self, forKey: SchemaKey("bits"))
    offset = try values.decode(Int.self, forKey: SchemaKey("offset"))
    set = try values.decode(String.self, forKey: SchemaKey("set"))
    encoding =
        try values.decode(RegisterEncoding.self, forKey: SchemaKey("encoding"))
    format = try values.decode(RegisterFormat.self, forKey: SchemaKey("format"))
    numbers =
        try values.decode(RegisterNumberDefinition.self,
                          forKey: SchemaKey("numbers"))
    relations =
        try values.decode(RegisterRelationDefinition.self,
                          forKey: SchemaKey("relations"))
    feature = try values.decode(String.self, forKey: SchemaKey("feature"))
    type = try values.decodeIfPresent(String.self, forKey: SchemaKey("type"))
    platforms =
        try values.decodeIfPresent(Array<RegisterPlatform>.self,
                                   forKey: SchemaKey("platforms")) ?? []
  }
}

internal struct RegisterProfileDefinition: Decodable {
  internal let profile: String
  internal let architecture: String
  internal let layout: ProfileLayout
  internal let sets: Array<RegisterSetDefinition>
  internal let features: Array<RegisterFeatureDefinition>
  internal let registers: Array<RegisterDefinition>

  internal init(from decoder: Decoder) throws {
    let keys: Set<String> = [
      "profile", "architecture", "layout", "sets", "features", "registers",
    ]
    let values = try container(decoder, keys: keys)
    profile = try values.decode(String.self, forKey: SchemaKey("profile"))
    architecture =
        try values.decode(String.self, forKey: SchemaKey("architecture"))
    layout = try values.decode(ProfileLayout.self, forKey: SchemaKey("layout"))
    sets =
        try values.decode(Array<RegisterSetDefinition>.self,
                          forKey: SchemaKey("sets"))
    features =
        try values.decode(Array<RegisterFeatureDefinition>.self,
                          forKey: SchemaKey("features"))
    registers =
        try values.decode(Array<RegisterDefinition>.self,
                          forKey: SchemaKey("registers"))
  }
}

internal func decode(_ source: String) throws(DSXCodeGenError)
    -> RegisterProfileDefinition {
  do {
    return try YAMLDecoder().decode(RegisterProfileDefinition.self,
                                    from: source)
  } catch let error as DSXCodeGenError {
    throw error
  } catch {
    throw .schema(String(describing: error))
  }
}
