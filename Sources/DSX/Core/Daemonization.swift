// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum DaemonizationError: Error, Equatable, Sendable {
  case system(CInt)
}

extension DaemonizationError: CustomStringConvertible {
  internal var description: String {
    switch self {
    case .system(let code): "unable to daemonize server (\(code))"
    }
  }
}

internal enum DaemonizationOrder: Sendable {
  case before
  case after
}

internal enum Daemonization {
  internal static func enabled(_ input: consuming String) -> Bool {
    var value = consume input
    return value.withUTF8 { value in
      truth(value)
    }
  }
}

private func truth(_ value: UnsafeBufferPointer<UInt8>) -> Bool {
  guard value.count <= 4 else {
    return false
  }
  var word: UInt32 = 0
  for byte in value {
    let byte = if byte >= UInt8(ascii: "A"), byte <= UInt8(ascii: "Z") {
      byte + UInt8(ascii: "a") - UInt8(ascii: "A")
    } else {
      byte
    }
    word = word << 8 | UInt32(byte)
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
