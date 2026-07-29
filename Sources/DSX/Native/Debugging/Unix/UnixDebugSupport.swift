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
internal import DSXShims

internal enum UnixDebugToken: Sendable {
  case ready
  case process(pid_t, CInt?)
}

internal enum UnixDebugPending: Sendable {
  case output(Debuggee.Output)
  case ready
  case status(pid_t, CInt)
}

#if os(anyAppleOS) || os(FreeBSD) || os(OpenBSD)
extension NativeDebugControl {
  internal func watchpoints(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Int {
    guard self.process == process else {
      throw .process
    }
    return try HardwareBreakpoint.capacity ?? 0
  }

  internal mutating func discard(_: borrowing Debuggee.Fork)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  internal mutating func close() throws(Debuggee.Error) {
    guard let process else {
      return
    }
    try detach(process, stopped: false)
  }

  internal func complete(_: borrowing Debuggee.Event) throws(Debuggee.Error) {
  }

  internal func discard(_: borrowing Debuggee.Event) throws(Debuggee.Error) {
  }

  internal func syscalls(_ calls: consuming Array<UInt64>?)
      throws(Debuggee.Error) {
    guard calls == nil else {
      throw .unsupported
    }
  }
}
#endif

internal enum UnixDebugProcess {
  internal static func failure(_ code: CInt) -> Debuggee.Error {
    if code == EINVAL {
      .state
    } else {
      UnixError.debuggee(code, invalid: .process, support: true)
    }
  }
}

extension ProcessIdentifier {
  @_transparent
  internal var native: pid_t {
    get throws(Debuggee.Error) {
      guard rawValue <= UInt64(pid_t.max) else {
        throw .process
      }
      return pid_t(rawValue)
    }
  }

  internal func owned(by current: ProcessIdentifier?) throws(Debuggee.Error)
      -> pid_t {
    guard current == self else {
      throw .process
    }
    return try native
  }
}

extension ThreadIdentifier {
  @_transparent
  internal var native: pid_t {
    get throws(Debuggee.Error) {
      guard rawValue <= UInt64(pid_t.max) else {
        throw .thread
      }
      return pid_t(rawValue)
    }
  }
}

extension ProcessThreadIdentifier {
  @_transparent
  internal var native: pid_t {
    get throws(Debuggee.Error) {
      guard process.rawValue <= UInt64(pid_t.max),
          thread.rawValue <= UInt64(pid_t.max) else {
        throw .thread
      }
      return pid_t(thread.rawValue)
    }
  }
}

extension UnixWaitStatus {
  internal static func event(_ status: CInt, process: ProcessIdentifier,
                             thread: ThreadIdentifier? = nil)
      -> Debuggee.Event {
    let selected = thread ?? ThreadIdentifier(rawValue: process.rawValue)
    let identifier = ProcessThreadIdentifier(process: process, thread: selected)
    if stopped(status) {
      let signal = signal(status)
      let reason: Debuggee.StopReason = switch signal {
      case SIGTRAP: .trace
      default: .signal(signal)
      }
      return .stopped(Debuggee.Stop(thread: identifier, reason: reason))
    }
    return if let exit = exit(status) {
      .exited(process, exit)
    } else {
      .stopped(Debuggee.Stop(thread: identifier, reason: .signal(0)))
    }
  }

}
#endif
