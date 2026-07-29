// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal enum WindowsThread {}

private func capture() throws(Debuggee.Error) -> WindowsHandle {
  let raw = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0)
  guard let handle = WindowsHandle(raw) else {
    throw WindowsError.debuggee(GetLastError(), invalid: .thread)
  }
  return handle
}

extension ProcessIdentifier {
  internal var threads: Array<ProcessThreadIdentifier> {
    get throws(Debuggee.Error) {
      let snapshot = try capture()
      return try NativeThread.identifiers(self, snapshot: snapshot)
    }
  }
}

extension WindowsThread {
  @inline(__always)
  internal static func snapshot(_: borrowing Span<Debuggee.Process>)
      throws(Debuggee.Error) -> WindowsHandle {
    try capture()
  }

  internal static func identifiers(_ process: ProcessIdentifier,
                                   snapshot: borrowing WindowsHandle)
      throws(Debuggee.Error) -> Array<ProcessThreadIdentifier> {
    let owner = try process.native
    var entry = THREADENTRY32()
    entry.dwSize = DWORD(MemoryLayout<THREADENTRY32>.size)
    var threads = Array<ProcessThreadIdentifier>()
    guard Thread32First(snapshot.value, &entry) else {
      let code = GetLastError()
      if code == ERROR_NO_MORE_FILES {
        return threads
      }
      throw WindowsError.debuggee(code, invalid: .thread)
    }
    repeat {
      if entry.th32OwnerProcessID == owner {
        let thread = ThreadIdentifier(rawValue: UInt64(entry.th32ThreadID))
        threads.append(ProcessThreadIdentifier(process: process,
                                               thread: thread))
      }
    } while Thread32Next(snapshot.value, &entry)
    let code = GetLastError()
    guard code == ERROR_NO_MORE_FILES else {
      throw WindowsError.debuggee(code, invalid: .thread)
    }
    return threads
  }
}

extension ProcessThreadIdentifier {
  internal var alive: Bool {
    get throws(Debuggee.Error) {
      let identifier = try thread.native
      let raw = OpenThread(THREAD_QUERY_LIMITED_INFORMATION, false, identifier)
      guard let raw else {
        return switch GetLastError() {
        case ERROR_INVALID_PARAMETER: false
        case let code: throw WindowsError.debuggee(code, invalid: .thread)
        }
      }
      let handle = WindowsHandle(raw)
      _ = handle.value
      return true
    }
  }

  internal var info: Debuggee.Thread.Info {
    get throws(Debuggee.Error) {
      guard try alive else {
        throw .thread
      }
      return Debuggee.Thread.Info(thread: self)
    }
  }
}

#endif
