// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Span where Element == UInt8 {
  internal var basename: Range<Int> {
    var start = 0
    for index in 0 ..< count where NativeFileSystem.separates(self[index]) {
      start = index + 1
    }
    return start ..< count
  }
}
