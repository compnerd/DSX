// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import DSXShims
internal import WinSDK

private let kThreadBasicInformation: CInt = 0

private typealias WindowsThreadBasicInformation = dsx_thread_basic_information

private func NtQueryInformationThread(_ thread: HANDLE, _ information: CInt,
                                      _ output: UnsafeMutableRawPointer,
                                      _ size: ULONG,
                                      _ returned: UnsafeMutablePointer<ULONG>?)
    -> LONG {
  dsx_NtQueryInformationThread(thread, information, output, size, returned)
}

extension ProcessThreadIdentifier {
  internal init(_ thread: DWORD, process: ProcessIdentifier) {
    self.init(process: process,
              thread: ThreadIdentifier(rawValue: UInt64(thread)))
  }

  internal var tib: Debuggee.Address {
    get throws(Debuggee.Error) {
      let identifier = try thread.native
      let raw = OpenThread(THREAD_QUERY_INFORMATION, false, identifier)
      guard let handle = WindowsHandle(raw) else {
        throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
      }
      var information = WindowsThreadBasicInformation()
      let size = ULONG(MemoryLayout<WindowsThreadBasicInformation>.size)
      let status = withUnsafeMutablePointer(to: &information) { information in
        NtQueryInformationThread(handle.value, kThreadBasicInformation,
                                 information, size, nil)
      }
      guard status >= 0 else {
        throw .system(CInt(status))
      }
      guard let block = information.TebBaseAddress else {
        throw .thread
      }
      return Debuggee.Address(rawValue: UInt64(UInt(bitPattern: block)))
    }
  }
}

#endif
