// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

extension Debuggee.Event {
  internal init(status: CInt, process: ProcessIdentifier,
                thread: ThreadIdentifier? = nil) {
    let selected = thread ?? ThreadIdentifier(rawValue: process.rawValue)
    let identifier = ProcessThreadIdentifier(process: process, thread: selected)
    let decoded = UnixWaitStatus(status)
    if decoded.stopped {
      let signal = decoded.signal
      let reason: Debuggee.StopReason = switch signal {
      case SIGTRAP: .trace
      default: .signal(signal)
      }
      self = .stopped(Debuggee.Stop(thread: identifier, reason: reason))
      return
    }
    self = if let exit = decoded.exit {
      .exited(process, exit)
    } else {
      .stopped(Debuggee.Stop(thread: identifier, reason: .signal(0)))
    }
  }
}
#endif
