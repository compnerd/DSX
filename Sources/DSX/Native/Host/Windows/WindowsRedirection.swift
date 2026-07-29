// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal enum WindowsRedirection: ~Copyable {
  case borrowed(HANDLE?)
  case owned(WindowsHandle)

  @inline(never)
  internal init(_ path: borrowing String?, standard: DWORD, access: DWORD,
                creation: DWORD, directory: borrowing String? = nil,
                security: inout SECURITY_ATTRIBUTES) throws(Debuggee.Error) {
    guard let path = copy path else {
      let handle = GetStdHandle(standard)
      if handle == INVALID_HANDLE_VALUE {
        throw Debuggee.Error(process: GetLastError())
      }
      guard let handle else {
        self = .borrowed(nil)
        return
      }
      var duplicate: HANDLE?
      let process = GetCurrentProcess()
      guard DuplicateHandle(process, handle, process, &duplicate, 0, true,
                            DWORD(DUPLICATE_SAME_ACCESS)),
          let owned = WindowsHandle(duplicate) else {
        throw Debuggee.Error(process: GetLastError())
      }
      self = .owned(owned)
      return
    }
    let resolved = try WindowsFileSystem.resolve(path, directory: directory)
    let handle = withUTF16CString(resolved) { path in
      CreateFileW(path, access, FILE_SHARE_READ | FILE_SHARE_WRITE, &security,
                  creation, FILE_ATTRIBUTE_NORMAL, nil)
    }
    guard let handle = WindowsHandle(handle) else {
      throw Debuggee.Error(process: GetLastError())
    }
    self = .owned(handle)
  }

  internal var value: HANDLE? {
    borrowing get {
      switch self {
      case .borrowed(let value): value
      case .owned(let handle): handle.value
      }
    }
  }
}
#endif
