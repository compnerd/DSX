// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(i386) || arch(x86_64))
internal import WinSDK

extension WindowsDebugControl {
  internal mutating func prepare(_ thread: WindowsDebugThread)
      throws(Debuggee.Error) {
    let flags = CONTEXT_CONTROL | CONTEXT_INTEGER | CONTEXT_DEBUG_REGISTERS
    var context = try CONTEXT(thread.handle, flags: flags)
    // Delivery of a previously captured exception can replace the context
    // prepared before the event arrived. Restore the selected operation.
    if thread.execution == .stepping {
      context.step()
    }
    try context.resume(thread.handle)
#if arch(x86_64)
    guard let restoration else {
      return
    }
    if context.Rip == restoration.rawValue {
      try preserve(context)
    }
#endif
  }
}
#endif
