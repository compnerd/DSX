// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(arm64) || arch(i386) || arch(x86_64))
internal import WinSDK

internal enum WindowsContext {
  internal static func snapshot(_ handle: HANDLE,
                                flags: DWORD) throws(Debuggee.Error)
      -> CONTEXT {
    var context = CONTEXT()
    context.ContextFlags = flags
    guard GetThreadContext(handle, &context) else {
      throw WindowsError.debuggee(GetLastError(), invalid: .thread)
    }
    return context
  }

  internal static func commit(_ context: borrowing CONTEXT,
                              to handle: HANDLE) throws(Debuggee.Error) {
    var context = copy context
    guard SetThreadContext(handle, &context) else {
      throw WindowsError.debuggee(GetLastError(), invalid: .thread)
    }
  }

  internal static func modify(_ handle: HANDLE, flags: DWORD,
                              _ body: (inout CONTEXT) -> Void)
      throws(Debuggee.Error) {
    var context = try snapshot(handle, flags: flags)
    body(&context)
    try commit(context, to: handle)
  }

}
#endif
