// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsDebugControl {
  internal mutating func prepare(_ thread: WindowsDebugThread,
                                 stepping: Bool = false)
      throws(Debuggee.Error) {
    let flags = CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_DEBUG_REGISTERS
    var context = try CONTEXT(thread.handle, flags: flags)
    // Delivery of a previously captured exception can replace the context
    // prepared before the event arrived. Restore the selected operation.
    if stepping || thread.execution == .stepping {
      context.step()
    }
#if arch(arm64)
    try context.commit(to: thread.handle)
#else
    try context.resume(thread.handle)
#endif
    guard let restoration else {
      return
    }
#if arch(i386)
    let pc = UInt64(context.Eip)
#elseif arch(x86_64)
    let pc = context.Rip
#else
    let pc = context.Pc
#endif
    if pc == restoration.rawValue {
      try preserve(context)
    }
  }
}
#endif
