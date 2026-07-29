// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension String {
  internal var affirmative: Bool {
    let value = utf8Span.span
    guard value.count <= 4 else {
      return false
    }
    var word: UInt32 = 0
    for index in 0 ..< value.count {
      let byte = value[index]
      let lower = if byte >= UInt8(ascii: "A"), byte <= UInt8(ascii: "Z") {
        byte + UInt8(ascii: "a") - UInt8(ascii: "A")
      } else {
        byte
      }
      word = word << 8 | UInt32(lower)
    }
    let one = UInt32(UInt8(ascii: "1"))
    let yes = UInt32(UInt8(ascii: "y")) << 16
            | UInt32(UInt8(ascii: "e")) << 8
            | UInt32(UInt8(ascii: "s"))
    let truth = UInt32(UInt8(ascii: "t")) << 24
              | UInt32(UInt8(ascii: "r")) << 16
              | UInt32(UInt8(ascii: "u")) << 8
              | UInt32(UInt8(ascii: "e"))
    return switch word {
    case one, yes, truth: true
    default: false
    }
  }
}
