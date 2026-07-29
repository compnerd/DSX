// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

private let kPathFlags: ULONG =
    PATHCCH_ALLOW_LONG_PATHS | PATHCCH_CANONICALIZE_SLASHES
private let kPathTrailing: ULONG = PATHCCH_ENSURE_TRAILING_SLASH

internal enum WindowsPath {
  internal static func resolve(_ handle: HANDLE, process: Bool = false)
      throws(Debuggee.Error) -> String {
    let flags = FILE_NAME_NORMALIZED | VOLUME_NAME_DOS
    let requested = GetFinalPathNameByHandleW(handle, nil, 0, flags)
    guard requested > 0 else {
      throw error(GetLastError(), process: process)
    }
    return try withUnsafeTemporaryAllocation(of: WCHAR.self,
                                             capacity: Int(requested) + 1,
                                             { buffer throws(Debuggee.Error) in
      let count = GetFinalPathNameByHandleW(handle, buffer.baseAddress,
                                            DWORD(buffer.count), flags)
      guard count > 0, count < DWORD(buffer.count) else {
        throw error(GetLastError(), process: process)
      }
      return String(decoding: buffer.prefix(Int(count)), as: UTF16.self)
    })
  }

  internal static func canonical(_ path: String) throws(Debuggee.Error)
      -> String {
    var output =
        try Array<WCHAR>(repeating: 0, count: count(path.utf16.count + 8))
    let result: HRESULT = output.withUnsafeMutableBufferPointer { output in
      withUTF16CString(path) { path in
        PathCchCanonicalizeEx(output.baseAddress, output.count, path,
                              kPathFlags)
      }
    }
    guard result >= 0 else {
      throw failure(result)
    }
    return String(decodingCString: output, as: UTF16.self)
  }

  internal static func combine(_ base: String, _ path: String,
                               trailing: Bool = false) throws(Debuggee.Error)
      -> String {
    let requested = base.utf16.count + path.utf16.count + 8
    var output = try Array<WCHAR>(repeating: 0, count: count(requested))
    let options = trailing ? kPathFlags | kPathTrailing : kPathFlags
    let result: HRESULT = output.withUnsafeMutableBufferPointer { output in
      withUTF16CString(base) { base in
        withUTF16CString(path) { path in
          PathCchCombineEx(output.baseAddress, output.count, base, path,
                           options)
        }
      }
    }
    guard result >= 0 else {
      throw failure(result)
    }
    return String(decodingCString: output, as: UTF16.self)
  }
}

private func error(_ code: DWORD, process: Bool) -> Debuggee.Error {
  let invalid: Debuggee.Error = if process {
    .process
  } else {
    .system(CInt(bitPattern: code))
  }
  return WindowsError.debuggee(code, invalid: invalid)
}
#endif
