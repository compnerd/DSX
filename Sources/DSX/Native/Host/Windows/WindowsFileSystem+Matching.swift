// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsFileSystem {
  internal static func matches(_ path: borrowing Span<UInt8>, _ value: String,
                               component: Bool) -> Bool {
    let value = value.utf8Span.span
    let lhs = component ? path.basename : 0 ..< path.count
    let rhs = component ? value.basename : 0 ..< value.count
    if unicode(path, range: lhs) || unicode(value, range: rhs) {
      let source = String(decoding: path.extracting(lhs), as: UTF8.self)
      let candidate = String(decoding: value.extracting(rhs), as: UTF8.self)
      return source.matches(windows: candidate)
    }
    guard lhs.count == rhs.count else {
      return false
    }
    for index in 0 ..< lhs.count {
      let source = path[lhs.lowerBound + index]
      let candidate = value[rhs.lowerBound + index]
      if separates(source), separates(candidate) {
        continue
      }
      guard lowercase(source) == lowercase(candidate) else {
        return false
      }
    }
    return true
  }

  internal static func separates(_ byte: UInt8) -> Bool {
    byte == UInt8(ascii: "/") || byte == UInt8(ascii: "\\")
  }
}

private func lowercase(_ byte: UInt8) -> UInt8 {
  byte >= UInt8(ascii: "A") && byte <= UInt8(ascii: "Z")
      ? byte + UInt8(ascii: "a") - UInt8(ascii: "A") : byte
}

private func unicode(_ path: borrowing Span<UInt8>, range: Range<Int>) -> Bool {
  for index in range where path[index] >= 0x80 {
    return true
  }
  return false
}

#endif
