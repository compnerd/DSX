// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(i386) || arch(x86_64) || arch(arm64))
internal import WinSDK

extension WindowsDebugControl {
  internal func configure(_ site: borrowing BreakpointSite,
                          thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    if let thread {
      guard thread.process == process,
          thread.thread.rawValue <= UInt64(DWORD.max),
          let handle = threads[DWORD(thread.thread.rawValue)]?.handle else {
        throw .thread
      }
      return try WindowsDebugControl.configure(site, enabled: enabled,
                                               handle: handle)
    }
    for thread in threads.values {
      try WindowsDebugControl.configure(site, enabled: enabled,
                                        handle: thread.handle)
    }
  }

  internal func restore(_ thread: DWORD) throws(Debuggee.Error) {
    guard let handle = threads[thread]?.handle else {
      throw .thread
    }
    for record in breakpoints {
      if let selection = record.thread,
          selection.thread.rawValue != UInt64(thread) {
        continue
      }
      try WindowsDebugControl.configure(record.site, enabled: true,
                                        handle: handle)
    }
  }
}
#endif
