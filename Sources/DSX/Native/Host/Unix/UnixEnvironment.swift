// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
extension Host {
  internal static func precedes(_ lhs: String, _ rhs: String) -> Bool {
    lhs.utf8.lexicographicallyPrecedes(rhs.utf8)
  }
}

internal enum UnixEnvironment {
  internal typealias Unit = UInt8

  internal static func read() throws(Debuggee.Error) -> Array<Unit> {
    var values = Array<Unit>()
    guard var cursor = variables() else {
      return values
    }
    while let pointer = cursor.pointee {
      var index = 0
      while pointer[index] != 0 {
        values.append(UInt8(bitPattern: pointer[index]))
        index += 1
      }
      values.append(0)
      cursor += 1
    }
    return values
  }

  internal static func encode(_ value: String, into bytes: inout Array<Unit>) {
    bytes.append(contentsOf: value.utf8)
  }

  internal static func compare(_ bytes: UnsafeBufferPointer<Unit>,
                               lhs: Range<Int>, rhs: Range<Int>) -> CInt {
    for index in 0 ..< min(lhs.count, rhs.count) {
      let left = CInt(bytes[lhs.lowerBound + index])
      let right = CInt(bytes[rhs.lowerBound + index])
      let order = left - right
      if order != 0 {
        return order
      }
    }
    return lhs.count == rhs.count ? 0 : (lhs.count < rhs.count ? -1 : 1)
  }
}
#endif
