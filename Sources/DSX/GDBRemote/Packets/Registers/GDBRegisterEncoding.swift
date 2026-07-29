// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension RegisterEncoding {
  internal var name: StaticString {
    switch self {
    case .flags: "uint"
    case .ieee: "ieee754"
    case .signed: "sint"
    case .unsigned: "uint"
    case .vector: "vector"
    }
  }
}

extension RegisterFormat {
  internal var name: StaticString {
    switch self {
    case .binary: "binary"
    case .decimal: "decimal"
    case .float: "float"
    case .hexadecimal: "hex"
    case .vector: "vector-uint8"
    }
  }
}

extension RegisterRole {
  internal var name: StaticString? {
    switch self {
    case .argument(let index):
      switch index {
      case 1: "arg1"
      case 2: "arg2"
      case 3: "arg3"
      case 4: "arg4"
      case 5: "arg5"
      case 6: "arg6"
      case 7: "arg7"
      case 8: "arg8"
      default: "arg"
      }
    case .flags: "flags"
    case .frame: "fp"
    case .link: "ra"
    case .program: "pc"
    case .result: nil
    case .stack: "sp"
    case .thread: "tp"
    }
  }
}
