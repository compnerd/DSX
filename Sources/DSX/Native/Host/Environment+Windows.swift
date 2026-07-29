// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension Host {
  @inline(never)
  internal static func precedes(_ lhs: String, _ rhs: String) -> Bool {
    withUTF16CString(lhs) { lhs in
      withUTF16CString(rhs) { rhs in
        CompareStringOrdinal(lhs, -1, rhs, -1, true) == CSTR_LESS_THAN
      }
    }
  }
}

internal enum WindowsEnvironment {
  internal typealias Unit = WCHAR

  internal static subscript(_ name: String) -> String {
    get throws(Debuggee.Error) {
      var capacity: DWORD = 0
      while true {
        var buffer = Array<WCHAR>(repeating: 0, count: Int(capacity))
        let (size, error) = buffer.withUnsafeMutableBufferPointer { buffer in
          withUTF16CString(name) { name in
            SetLastError(0)
            let size =
                GetEnvironmentVariableW(name, buffer.baseAddress, capacity)
            return (size, GetLastError())
          }
        }
        if size == 0 {
          guard error == 0 else {
            throw WindowsError.debuggee(error)
          }
          return ""
        }
        if size < capacity {
          return String(decoding: buffer.prefix(Int(size)), as: UTF16.self)
        }
        capacity = size
      }
    }
  }

  internal static func read() throws(Debuggee.Error) -> Array<Unit> {
    guard let block = GetEnvironmentStringsW() else {
      throw WindowsError.debuggee(GetLastError())
    }
    defer {
      _ = FreeEnvironmentStringsW(block)
    }
    var count = 0
    while block[count] != 0 {
      while block[count] != 0 {
        count += 1
      }
      count += 1
    }
    return Array(UnsafeBufferPointer(start: block, count: count))
  }

  @inline(never)
  internal static func encode(_ value: String, into bytes: inout Array<Unit>) {
    bytes.append(contentsOf: value.utf16)
  }

  internal static func compare(_ bytes: UnsafeBufferPointer<Unit>,
                               lhs: Range<Int>, rhs: Range<Int>) -> CInt {
    guard let base = bytes.baseAddress else {
      preconditionFailure()
    }
    let order = CompareStringOrdinal(base + lhs.lowerBound, CInt(lhs.count),
                                     base + rhs.lowerBound, CInt(rhs.count),
                                     true)
    return order - CSTR_EQUAL
  }
}
#endif
