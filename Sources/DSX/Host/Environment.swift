// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum ProcessEnvironment {
  internal typealias Unit = NativeEnvironment.Unit

  internal static func resolve(_ changes: borrowing Span<Debuggee.Environment>,
                               inheriting storage: consuming Array<Unit>)
      throws(Debuggee.Error) -> Array<Unit> {
    let inherited = storage.count
    var entries = Array<Range<Int>>()
    var start = 0
    while start < storage.count {
      var end = start
      var separator: Int?
      while end < storage.count, storage[end] != 0 {
        // Windows also inherits per-drive entries such as "=C:=C:\\".
        if end > start, storage[end] == 61, separator == nil {
          separator = end
        }
        end += 1
      }
      guard end < storage.count else {
        throw .state
      }
      entries.append(start ..< (separator ?? end))
      start = end + 1
    }
    for index in 0 ..< changes.count {
      let entry = changes[index]
      guard entry.valid else {
        throw .state
      }
      let start = storage.count
      NativeEnvironment.encode(entry.name, into: &storage)
      let name = start ..< storage.count
      guard name.count <= Int(CInt.max) else {
        throw .state
      }
      if let value = entry.value {
        storage.append(61)
        NativeEnvironment.encode(value, into: &storage)
      }
      entries.append(name)
      storage.append(0)
    }
    return storage.withUnsafeBufferPointer { storage in
      entries.order { lhs, rhs in
        let order = NativeEnvironment.compare(storage, lhs: lhs, rhs: rhs)
        return order == 0 ? lhs.lowerBound < rhs.lowerBound : order < 0
      }
      var result = Array<Unit>()
      for index in entries.indices {
        let entry = entries[index]
        if entry.lowerBound >= inherited, storage[entry.upperBound] == 0 {
          continue
        }
        if index + 1 < entries.count,
            NativeEnvironment.compare(storage, lhs: entry,
                                      rhs: entries[index + 1]) == 0 {
          continue
        }
        var cursor = entry.lowerBound
        while storage[cursor] != 0 {
          result.append(storage[cursor])
          cursor += 1
        }
        result.append(0)
      }
      result.append(0)
      if result.count == 1 {
        result.append(0)
      }
      return result
    }
  }
}
