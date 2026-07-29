// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension ProcessIdentifier {
  internal var info: Debuggee.Process.Info {
    get throws(Debuggee.Error) {
      var record = try entry
      return try information(&record)
    }
  }

  internal func information(_ record: inout PROCESSENTRY32W)
      throws(Debuggee.Error) -> Debuggee.Process.Info {
    let parent: ProcessIdentifier? = if record.th32ParentProcessID > 0 {
      ProcessIdentifier(rawValue: UInt64(record.th32ParentProcessID))
    } else {
      nil
    }
    let architecture = try machine
    return Debuggee.Process.Info(process: self, parent: parent,
                                 name: decode(&record.szExeFile),
                                 architecture: architecture)
  }

  private var entry: PROCESSENTRY32W {
    get throws(Debuggee.Error) {
      let process = try native
      let raw = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
      guard let handle = WindowsHandle(raw) else {
        throw WindowsError.debuggee(GetLastError(), invalid: .process)
      }
      var entry = PROCESSENTRY32W()
      entry.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
      guard Process32FirstW(handle.value, &entry) else {
        throw WindowsError.debuggee(GetLastError(), invalid: .process)
      }
      repeat {
        if entry.th32ProcessID == process {
          return entry
        }
      } while Process32NextW(handle.value, &entry)
      throw .process
    }
  }

  private var machine: String {
    get throws(Debuggee.Error) {
      let identifier = try native
      let raw =
          OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, identifier)
      guard let raw else {
        throw WindowsError.debuggee(GetLastError(), invalid: .process)
      }
      let handle = WindowsHandle(raw)
      var guest: USHORT = 0
      var native: USHORT = 0
      guard IsWow64Process2(handle.value, &guest, &native) else {
        throw WindowsError.debuggee(GetLastError(), invalid: .process)
      }
      let machine = guest == IMAGE_FILE_MACHINE_UNKNOWN ? native : guest
      return switch machine {
      case IMAGE_FILE_MACHINE_ARM:
        "arm"
      case IMAGE_FILE_MACHINE_ARM64:
        "arm64"
      case IMAGE_FILE_MACHINE_I386:
        "i386"
      case IMAGE_FILE_MACHINE_AMD64:
        "x86_64"
      default:
        "unknown"
      }
    }
  }
}

internal struct WindowsProcessCursor: ~Copyable, Sendable {
  private let handle: WindowsHandle
  private var record: PROCESSENTRY32W
  private var started: Bool
  private var complete: Bool

  internal init() throws(Debuggee.Error) {
    let raw = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)
    guard let handle = WindowsHandle(raw) else {
      throw WindowsError.debuggee(GetLastError(), invalid: .process)
    }
    self.handle = consume handle
    record = PROCESSENTRY32W()
    record.dwSize = DWORD(MemoryLayout<PROCESSENTRY32W>.size)
    started = false
    complete = false
  }

  internal mutating func next() throws(Debuggee.Error)
      -> Debuggee.Process.Info? {
    while complete == false {
      let result = if started {
        Process32NextW(handle.value, &record)
      } else {
        Process32FirstW(handle.value, &record)
      }
      started = true
      guard result else {
        let code = GetLastError()
        complete = true
        guard code == ERROR_NO_MORE_FILES else {
          throw WindowsError.debuggee(code, invalid: .process)
        }
        return nil
      }
      if record.th32ProcessID > 0 {
        let process = ProcessIdentifier(rawValue: UInt64(record.th32ProcessID))
        return try process.information(&record)
      }
    }
    return nil
  }
}
#endif
