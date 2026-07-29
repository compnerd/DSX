// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension ProcessIdentifier {
  internal var threads: Array<ProcessThreadIdentifier> {
    get throws(Debuggee.Error) {
      let raw = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
      guard let snapshot = WindowsHandle(raw) else {
        throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
      }
      let owner = try native
      var entry = THREADENTRY32()
      entry.dwSize = DWORD(MemoryLayout<THREADENTRY32>.size)
      var threads = Array<ProcessThreadIdentifier>()
      guard Thread32First(snapshot.value, &entry) else {
        let code = GetLastError()
        if code == ERROR_NO_MORE_FILES {
          return threads
        }
        throw Debuggee.Error(windows: code, invalid: .thread)
      }
      repeat {
        if entry.th32OwnerProcessID == owner {
          let thread = ThreadIdentifier(rawValue: UInt64(entry.th32ThreadID))
          threads.append(ProcessThreadIdentifier(process: self, thread: thread))
        }
      } while Thread32Next(snapshot.value, &entry)
      let code = GetLastError()
      guard code == ERROR_NO_MORE_FILES else {
        throw Debuggee.Error(windows: code, invalid: .thread)
      }
      return threads
    }
  }
}

extension ProcessThreadIdentifier {
  internal var info: Debuggee.Thread.Info {
    get throws(Debuggee.Error) {
      let identifier = try thread.native
      let raw = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, false, identifier)
      guard let handle = WindowsHandle(raw) else {
        throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
      }
      var description: PWSTR?
      let result = GetThreadDescription(handle.value, &description)
      guard result >= 0 else {
        throw .system(CInt(result))
      }
      guard let description else {
        return Debuggee.Thread.Info(thread: self)
      }
      defer { _ = LocalFree(description) }
      let name = String(decodingCString: description, as: UTF16.self)
      return Debuggee.Thread.Info(thread: self, name: name.isEmpty ? nil : name)
    }
  }
}

#endif
