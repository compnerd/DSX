// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && (arch(arm64) || arch(i386) || arch(x86_64))
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension LinuxDebugControl {
  internal func prepare(_: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let process, !breakpoints.isEmpty else {
      return
    }
    let threads = try process.threads(living: false)
    for record in breakpoints {
      try record.site.configure(process, list: threads.span,
                                thread: record.thread, enabled: true)
    }
  }

  internal mutating func breakpoint(_ process: ProcessIdentifier,
                                    site: borrowing BreakpointSite,
                                    thread: ProcessThreadIdentifier?,
                                    enabled: Bool) throws(Debuggee.Error) {
    guard self.process == process else {
      throw .process
    }
    if enabled {
      breakpoints.update(site, thread: thread, enabled: true)
    }
    try site.configure(process, thread: thread, enabled: enabled)
    if enabled == false {
      breakpoints.update(site, thread: thread, enabled: false)
    }
  }

  internal func inherit(_ process: ProcessIdentifier,
                        thread: pid_t) throws(Debuggee.Error) {
    let native = ThreadIdentifier(rawValue: UInt64(thread))
    let identifier = ProcessThreadIdentifier(process: process, thread: native)
    for record in breakpoints {
      if let selection = record.thread, selection != identifier {
        continue
      }
      try record.site.configure(process, thread: identifier, enabled: true)
    }
  }
}

extension BreakpointSite {
  fileprivate func configure(_ process: ProcessIdentifier,
                             thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    if let thread {
      return try configure(thread, process: process, enabled: enabled)
    }
    let threads = try process.threads(living: false)
    try configure(process, list: threads.span, thread: nil, enabled: enabled)
  }

  fileprivate func configure(_ process: ProcessIdentifier,
                             list: borrowing Span<ProcessThreadIdentifier>,
                             thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    if let thread {
      return try configure(thread, process: process, enabled: enabled)
    }
    for index in 0 ..< list.count {
      do {
        try configure(list[index], process: process, enabled: enabled)
      } catch .thread {
        continue
      }
    }
  }

  private func configure(_ thread: ProcessThreadIdentifier,
                         process: ProcessIdentifier, enabled: Bool)
      throws(Debuggee.Error) {
    guard thread.process == process else {
      throw .thread
    }
    try LinuxDebugControl.configure(thread.thread.native, site: self,
                                    enabled: enabled)
  }
}
#endif
