// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension UInt8 {
  internal var hexadecimal: UInt8 {
    let value = self & 0x0f
    return value < 10
        ? value + UInt8(ascii: "0") : value - 10 + UInt8(ascii: "a")
  }

  internal init?(hex byte: UInt8) {
    let value: UInt8? = switch byte {
    case UInt8(ascii: "0") ... UInt8(ascii: "9"):
      byte - UInt8(ascii: "0")
    case UInt8(ascii: "A") ... UInt8(ascii: "F"):
      byte - UInt8(ascii: "A") + 10
    case UInt8(ascii: "a") ... UInt8(ascii: "f"):
      byte - UInt8(ascii: "a") + 10
    default: nil
    }
    guard let value else {
      return nil
    }
    self = value
  }
}
