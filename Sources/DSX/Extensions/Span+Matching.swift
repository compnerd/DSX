// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Span where Element == UInt8 {
  internal func matches(at start: Int, value: StaticString) -> Bool {
    value.withUTF8Buffer { text in
      guard start >= 0, start <= count, text.count <= count - start else {
        return false
      }
      for index in 0 ..< text.count {
        if self[start + index] != text[index] {
          return false
        }
      }
      return true
    }
  }
}
