// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import DSXShims
internal import Synchronization
internal import WinSDK

// DbgHelp is single-threaded, including calls for unrelated processes.
private let kDumpLock = Mutex(())

private typealias MiniDumpWriteDumpBinding =
    LazyBinding<DSXShims.MiniDumpWriteDump_t>

extension MiniDumpWriteDumpBinding {
  fileprivate func callAsFunction(_ process: HANDLE, _ identifier: DWORD,
                                  _ file: HANDLE, _ type: MINIDUMP_TYPE)
      -> Bool {
    dsx_MiniDumpWriteDump(function, process, identifier, file, type, nil, nil,
                          nil)
  }
}

private let MiniDumpWriteDump: MiniDumpWriteDumpBinding? = {
  let module = withUTF16CString("dbghelp.dll") { path in
    LoadLibraryExW(path, nil, LOAD_LIBRARY_SEARCH_SYSTEM32)
  }
  guard let module else {
    return nil
  }
  return MiniDumpWriteDumpBinding(module: module, "MiniDumpWriteDump")
}()

internal enum WindowsCoreDump {
  internal static func dump(_ process: ProcessIdentifier, hint: String?)
      throws(Debuggee.Error) -> String {
    guard let MiniDumpWriteDump else {
      throw .unsupported
    }
    let identifier = try process.native
    let access = PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
    guard let handle =
        WindowsHandle(OpenProcess(access, false, identifier)) else {
      throw Debuggee.Error(windows: GetLastError())
    }
    let path = try temporary(hint)
    let raw = withUTF16CString(path) { path in
      CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, nil, OPEN_EXISTING,
                  FILE_ATTRIBUTE_NORMAL, nil)
    }
    guard let file = WindowsHandle(raw) else {
      let error = GetLastError()
      _ = withUTF16CString(path) { DeleteFileW($0) }
      throw Debuggee.Error(windows: error)
    }
    // DSX and its inferior have the same architecture. Saving here preserves
    // the inferior's context instead of capturing a 64-bit client's WoW64
    // host context when debugging a 32-bit process.
    let error = kDumpLock.withLock { _ in
      if MiniDumpWriteDump(handle.value, identifier, file.value,
                           MiniDumpWithFullMemoryInfo) {
        return DWORD(ERROR_SUCCESS)
      }
      return GetLastError()
    }
    _ = consume file
    guard error == ERROR_SUCCESS else {
      _ = withUTF16CString(path) { DeleteFileW($0) }
      throw Debuggee.Error(windows: error)
    }
    return path
  }

  private static func temporary(_ hint: String?) throws(Debuggee.Error)
      -> String {
    // The server owns this temporary file until the client transfers and
    // removes it. Never alias the client's destination, even on a shared
    // filesystem. Use the hinted directory when it is available remotely.
    if let hint,
        let directory = try? WindowsPath.parent(WindowsPath.canonical(hint)),
        let path = try? temporary(directory: directory) {
      return path
    }
    var directory = Array<WCHAR>(repeating: 0, count: Int(MAX_PATH) + 1)
    let count = GetTempPathW(DWORD(directory.count), &directory)
    guard count > 0 else {
      throw Debuggee.Error(windows: GetLastError())
    }
    guard Int(count) < directory.count else {
      throw Debuggee.Error(windows: DWORD(ERROR_INSUFFICIENT_BUFFER))
    }
    let path = String(decodingCString: directory, as: UTF16.self)
    return try temporary(directory: path)
  }

  private static func temporary(directory: String) throws(Debuggee.Error)
      -> String {
    var path = Array<WCHAR>(repeating: 0, count: Int(MAX_PATH) + 1)
    let result = withUTF16CString("dsx") { prefix in
      withUTF16CString(directory) { directory in
        GetTempFileNameW(directory, prefix, 0, &path)
      }
    }
    guard result > 0 else {
      throw Debuggee.Error(windows: GetLastError())
    }
    return String(decodingCString: path, as: UTF16.self)
  }
}
#endif
