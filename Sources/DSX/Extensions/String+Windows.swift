// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
extension String {
  internal init(command executable: borrowing String,
                arguments: borrowing Span<String>) {
    self.init(quoting: executable)
    for index in 0 ..< arguments.count {
      append(" ")
      append(String(quoting: arguments[index]))
    }
  }

  @inline(never)
  internal init(quoting argument: borrowing String) {
    let bytes = argument.utf8Span.span
    var quoted = bytes.isEmpty
    for index in 0 ..< bytes.count {
      let byte = bytes[index]
      if byte == UInt8(ascii: " ") || byte == UInt8(ascii: "\t") ||
          byte == UInt8(ascii: "\"") {
        quoted = true
        break
      }
    }
    guard quoted else {
      self = copy argument
      return
    }
    var result = [UInt8(ascii: "\"")]
    var slashes = 0
    for index in 0 ..< bytes.count {
      let byte = bytes[index]
      if byte == UInt8(ascii: "\\") {
        slashes += 1
        continue
      }
      let count = byte == UInt8(ascii: "\"") ? slashes * 2 + 1 : slashes
      for _ in 0 ..< count {
        result.append(UInt8(ascii: "\\"))
      }
      result.append(byte)
      slashes = 0
    }
    for _ in 0 ..< (slashes * 2) {
      result.append(UInt8(ascii: "\\"))
    }
    result.append(UInt8(ascii: "\""))
    self.init(decoding: result, as: UTF8.self)
  }
}
#endif
