// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

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

extension Decoder {
  internal func container(keys: Set<String>) throws
      -> KeyedDecodingContainer<SchemaKey> {
    let values = try container(keyedBy: SchemaKey.self)
    for key in values.allKeys {
      guard keys.contains(key.stringValue) else {
        throw DSXCodeGenError.schema("unknown field '\(key.stringValue)'")
      }
    }
    return values
  }
}
