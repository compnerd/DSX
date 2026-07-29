// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension OutputSpan where Element == UInt8 {
  internal mutating func append(_ output: borrowing Debuggee.Output)
      throws(Debuggee.Error) {
    guard freeCapacity >= output.count else {
      throw .state
    }
    for index in 0 ..< output.count {
      append(output.bytes[index])
    }
  }
}
