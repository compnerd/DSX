// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum LogSystem {
  internal static func write(_ descriptor: CInt,
                             _ buffer: UnsafeRawBufferPointer) -> Bool {
    var offset = 0
    while offset < buffer.count {
      let base = buffer.baseAddress!.advanced(by: offset)
      let count = output(descriptor, base, buffer.count - offset)
      guard count > 0 else {
        return false
      }
      offset += count
    }
    return true
  }
}
