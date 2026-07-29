// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

@inline(never)
internal func withUTF16CString<Result>(_ string: borrowing String,
                                       _ body: (UnsafePointer<WCHAR>) -> Result)
    -> Result {
  withUnsafeTemporaryAllocation(of: WCHAR.self, capacity: 260) { buffer in
    let value = WindowsCString(string, buffer: buffer)
    defer {
      _fixLifetime(value)
    }
    return body(value.value)
  }
}

private struct WindowsCString: ~Copyable, ~Escapable {
  private let owned: Bool
  fileprivate let value: UnsafeMutablePointer<WCHAR>

  @_lifetime(borrow buffer)
  @inline(never)
  fileprivate init(_ string: borrowing String,
                   buffer: UnsafeMutableBufferPointer<WCHAR>) {
    let count = string.utf16.count + 1
    owned = count > buffer.count
    value = owned ? UnsafeMutablePointer.allocate(capacity: count)
                  : buffer.baseAddress!
    let storage = UnsafeMutableBufferPointer(start: value, count: count)
    var output = OutputSpan(buffer: storage, initializedCount: 0)
    for unit in string.utf16 {
      output.append(unit)
    }
    output.append(0)
  }

  deinit {
    if owned {
      value.deallocate()
    }
  }
}

@inline(never)
internal func decode<Value>(_ value: inout Value) -> String {
  withUnsafePointer(to: &value) { value in
    let capacity = MemoryLayout<Value>.size / MemoryLayout<WCHAR>.size
    return value.withMemoryRebound(to: WCHAR.self,
                                   capacity: capacity) { value in
      var count = 0
      while count < capacity, value[count] != 0 {
        count += 1
      }
      return String(decoding: UnsafeBufferPointer(start: value, count: count),
                    as: UTF16.self)
    }
  }
}

extension String {
  internal func matches(windows candidate: borrowing String) -> Bool {
    guard let lhs = CInt(exactly: utf16.count),
        let rhs = CInt(exactly: candidate.utf16.count) else {
      return false
    }
    let capacity = 260
    return withUnsafeTemporaryAllocation(of: WCHAR.self, capacity: 2 * capacity,
                                         { buffer in
      let first = UnsafeMutableBufferPointer(rebasing: buffer[..<capacity])
      let second = UnsafeMutableBufferPointer(rebasing: buffer[capacity...])
      var source = WindowsCString(self, buffer: first)
      var candidate = WindowsCString(candidate, buffer: second)
      defer {
        _fixLifetime(source)
        _fixLifetime(candidate)
      }
      source.normalize(count: Int(lhs))
      candidate.normalize(count: Int(rhs))
      return CompareStringOrdinal(source.value, lhs, candidate.value, rhs,
                                  true) == CSTR_EQUAL
    })
  }
}

extension WindowsCString {
  fileprivate mutating func normalize(count: Int) {
    for index in 0 ..< count where value[index] == 0x005c {
      value[index] = 0x002f
    }
  }
}

#endif
