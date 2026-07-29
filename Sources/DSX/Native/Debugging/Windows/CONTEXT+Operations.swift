// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension CONTEXT {
  internal init(_ handle: HANDLE, flags: DWORD) throws(Debuggee.Error) {
    self.init()
    ContextFlags = flags
    guard GetThreadContext(handle, &self) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
    }
  }

  internal func commit(to handle: HANDLE) throws(Debuggee.Error) {
    var context = self
    guard SetThreadContext(handle, &context) else {
      throw Debuggee.Error(windows: GetLastError(), invalid: .thread)
    }
  }
}
#endif
