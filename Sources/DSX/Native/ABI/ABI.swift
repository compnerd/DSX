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

internal enum PointerWidth: Int, Sendable {
  case b32 = 32
  case b64 = 64
  case b128 = 128

  internal var bytes: Int { rawValue / 8 }
}

internal enum ABI: Sendable {
  internal static var width: PointerWidth {
#if _pointerBitWidth(_64)
    .b64
#elseif _pointerBitWidth(_32)
    .b32
#else
#error("Implement the native pointer width")
#endif
  }

  internal static var endian: Endian {
    .little
  }
}
