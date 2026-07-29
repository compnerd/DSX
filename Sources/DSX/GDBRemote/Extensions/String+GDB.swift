// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension String {
  internal init(hex input: borrowing Span<UInt8>) throws(GDBHandlerError) {
    guard input.count % 2 == 0 else {
      throw .malformed
    }
    let size = input.count / 2
    self = try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size,
                                             { raw throws(GDBHandlerError) in
      var output = OutputSpan(buffer: raw, initializedCount: 0)
      try output.decode(input)
      for index in 0 ..< output.count where output[index] == 0 {
        throw .malformed
      }
      return String(decoding: output.span, as: UTF8.self)
    })
  }
}
