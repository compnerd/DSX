// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum RegisterEncoding: String, Decodable {
  case flags
  case ieee
  case signed
  case unsigned
  case vector
}

internal enum RegisterFormat: String, Decodable {
  case binary
  case decimal
  case float
  case hexadecimal
  case vector
}

internal enum RegisterTypeKind: String, Decodable {
  case `enum`
  case flags
  case vector
}

internal enum RegisterRole: Hashable, Decodable {
  case flags
  case frame
  case link
  case program
  case result
  case stack
  case thread
  case argument(UInt8)

  internal init(from decoder: Decoder) throws {
    let value = try decoder.singleValueContainer().decode(String.self)
    self = switch value {
    case "flags": .flags
    case "frame": .frame
    case "link": .link
    case "program": .program
    case "result": .result
    case "stack": .stack
    case "thread": .thread
    default:
      if value.hasPrefix("argument"),
          let index = UInt8(value.dropFirst("argument".count)),
          index > 0, index < 0x80 {
        .argument(index)
      } else {
        throw DSXCodeGenError.schema("invalid register role '\(value)'")
      }
    }
  }
}
