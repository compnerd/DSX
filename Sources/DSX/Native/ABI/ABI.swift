// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum Endian: Sendable {
  case big
  case little

  internal var name: StaticString {
    switch self {
    case .big: "big"
    case .little: "little"
    }
  }
}

internal enum ABI: Sendable {
  internal static var endian: Endian {
    .little
  }
}
