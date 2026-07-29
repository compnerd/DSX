// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && (arch(arm64) || arch(i386) || arch(x86_64))
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension LinuxDebugControl {
  internal mutating func prepare(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let process, !breakpoints.isEmpty else {
      return
    }
    let threads = try process.threads(living: false)
    for record in breakpoints {
      try LinuxDebugControl.configure(process, list: threads.span,
                                      site: record.site, thread: record.thread,
                                      enabled: true)
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
    try LinuxDebugControl.configure(process, site: site, thread: thread,
                                    enabled: enabled)
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
      try LinuxDebugControl.configure(process, site: record.site,
                                      thread: identifier, enabled: true)
    }
  }

  private static func configure(_ process: ProcessIdentifier,
                                site: borrowing BreakpointSite,
                                thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    if let thread {
      guard thread.process == process,
          thread.thread.rawValue <= UInt64(pid_t.max) else {
        throw .thread
      }
      return try configure(pid_t(thread.thread.rawValue), site: site,
                           enabled: enabled)
    }
    let threads = try process.threads(living: false)
    try configure(process, list: threads.span, site: site, thread: nil,
                  enabled: enabled)
  }

  private static func configure(_ process: ProcessIdentifier,
                                list: borrowing Span<ProcessThreadIdentifier>,
                                site: borrowing BreakpointSite,
                                thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    if let thread {
      guard thread.process == process,
          thread.thread.rawValue <= UInt64(pid_t.max) else {
        throw .thread
      }
      return try configure(pid_t(thread.thread.rawValue), site: site,
                           enabled: enabled)
    }
    for index in 0 ..< list.count {
      do {
        let thread = pid_t(list[index].thread.rawValue)
        try configure(thread, site: site, enabled: enabled)
      } catch .thread {
        continue
      }
    }
  }
}
#endif
