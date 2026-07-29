// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsPath {
  internal static func system(_ path: String) -> Bool {
    var path = Array(path.utf16)
    path.append(0)
    return path.withUnsafeMutableBufferPointer { path in
      let stripped = PathCchStripPrefix(path.baseAddress, path.count)
      guard stripped >= 0 else {
        return false
      }
      var system = InlineArray<260, WCHAR> { _ in 0 }
      return withUnsafeMutablePointer(to: &system) { system in
        system.withMemoryRebound(to: WCHAR.self, capacity: 260) { system in
          let count = GetWindowsDirectoryW(system, 260)
          guard count > 0, count < 260, path.count > Int(count) else {
            return false
          }
          let equal = CompareStringOrdinal(path.baseAddress, CInt(count),
                                           system, CInt(count), true)
          return equal == CSTR_EQUAL && path[Int(count)] == 0x5c
        }
      }
    }
  }

  internal static func parent(_ path: String) throws(Debuggee.Error)
      -> String? {
    var output = Array(path.utf16)
    output.append(0)
    guard try parent(&output) else {
      return nil
    }
    return String(decodingCString: output, as: UTF16.self)
  }

  internal static func parent(_ path: inout Array<WCHAR>) throws(Debuggee.Error)
      -> Bool {
    let result: HRESULT = path.withUnsafeMutableBufferPointer { path in
      PathCchRemoveFileSpec(path.baseAddress, path.count)
    }
    guard result >= 0 else {
      throw failure(result)
    }
    return result != 1
  }

  internal static func root(_ path: String) -> Bool {
    withUTF16CString(path) { path in
      PathCchIsRoot(path)
    }
  }

  internal static func count(_ requested: Int) throws(Debuggee.Error) -> Int {
    guard requested <= 0x8000 else {
      throw .system(206)
    }
    return max(requested, 1)
  }

  internal static func failure(_ result: HRESULT) -> Debuggee.Error {
    let value = UInt32(truncatingIfNeeded: result)
    if value & 0xffff0000 == 0x80070000 {
      return WindowsError.debuggee(DWORD(value & 0x0000ffff))
    }
    return .system(CInt(bitPattern: value))
  }

}
#endif
