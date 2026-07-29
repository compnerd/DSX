// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsDebugControl {
  internal func configure(_ site: borrowing BreakpointSite,
                          thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    if let thread {
      guard thread.process == process,
          thread.thread.rawValue <= UInt64(DWORD.max),
          let selected = threads[DWORD(thread.thread.rawValue)] else {
        throw .thread
      }
      if try selected.exited {
        return
      }
      return try selected.configure(site, enabled: enabled)
    }
    // An exited thread remains owned until its queued exit event is consumed,
    // but no longer has a context on which to install or remove comparators.
    for thread in threads.values where try thread.exited == false {
      try thread.configure(site, enabled: enabled)
    }
  }

  internal func restore(_ identifier: DWORD) throws(Debuggee.Error) {
    guard let thread = threads[identifier] else {
      throw .thread
    }
    for record in breakpoints {
      if let selection = record.thread,
          selection.thread.rawValue != UInt64(identifier) {
        continue
      }
      try thread.configure(record.site, enabled: true)
    }
  }
}
#endif
