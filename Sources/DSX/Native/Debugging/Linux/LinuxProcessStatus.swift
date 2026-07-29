// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
/// The state and following fields of /proc/<pid>/stat.
internal struct LinuxProcessStatus: ~Escapable {
  private let fields: Span<UInt8>

  @_lifetime(copy bytes)
  internal init?(_ bytes: consuming Span<UInt8>) {
    // comm can contain spaces and parentheses; its final ')' ends the field.
    var close: Int?
    for index in 0 ..< bytes.count where bytes[index] == UInt8(ascii: ")") {
      close = index
    }
    guard let close, close + 2 < bytes.count,
        bytes[close + 1] == UInt8(ascii: " ") else {
      return nil
    }
    fields = bytes.extracting((close + 2)...)
  }

  internal var state: UInt8 { fields[0] }

  internal var parent: UInt64? {
    guard fields.count > 2, fields[1] == UInt8(ascii: " ") else {
      return nil
    }
    let tail = fields.extracting(2...)
    var end = 0
    while end < tail.count, tail[end] != UInt8(ascii: " ") {
      end += 1
    }
    return tail.extracting(..<end).decimal()
  }
}
#endif
