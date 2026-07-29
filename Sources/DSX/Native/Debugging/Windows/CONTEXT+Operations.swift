// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension CONTEXT {
  @inline(never)
  internal init(_ handle: HANDLE, flags: DWORD) throws(Debuggee.Error) {
    self.init()
    ContextFlags = flags
    guard GetThreadContext(handle, &self) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
    }
  }

  @inline(never)
  internal func commit(to handle: HANDLE) throws(Debuggee.Error) {
    let status = withUnsafePointer(to: self) { SetThreadContext(handle, $0) }
    guard status else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
    }
  }
}
#endif
