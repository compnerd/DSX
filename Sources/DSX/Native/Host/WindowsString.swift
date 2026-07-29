// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

@inline(never)
internal func withUTF16CString<Result>(_ string: borrowing String,
                                       _ body: (UnsafePointer<WCHAR>) -> Result)
    -> Result {
  let capacity = 260
  if string.utf16.count >= capacity {
    let storage = terminated(string)
    return storage.withUnsafeBufferPointer { buffer in
      guard let base = buffer.baseAddress else {
        preconditionFailure()
      }
      return body(base)
    }
  }
  return withUnsafeTemporaryAllocation(of: WCHAR.self,
                                       capacity: capacity) { buffer in
    var output = OutputSpan(buffer: buffer, initializedCount: 0)
    encode(string, into: &output)
    guard let base = buffer.baseAddress else {
      preconditionFailure()
    }
    return body(base)
  }
}

@inline(never)
private func terminated(_ string: borrowing String) -> Array<WCHAR> {
  let capacity = string.utf16.count + 1
  return Array(unsafeUninitializedCapacity: capacity) { buffer, count in
    var output = OutputSpan(buffer: buffer, initializedCount: 0)
    encode(string, into: &output)
    count = capacity
  }
}

@inline(never)
private func encode(_ string: borrowing String,
                    into output: inout OutputSpan<WCHAR>) {
  for unit in string.utf16 {
    output.append(unit)
  }
  output.append(0)
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
#endif
