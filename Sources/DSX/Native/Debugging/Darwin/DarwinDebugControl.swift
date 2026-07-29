// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal struct DarwinSuspension: Sendable {
  internal let thread: ThreadIdentifier
  internal let count: Int
}

internal struct DarwinDebugControl: Sendable {
  internal var process: ProcessIdentifier?
  internal var attached = false
  internal var status: CInt?
  internal var breakpoints = ActiveBreakpoints()
  internal var steps = Array<ProcessThreadIdentifier>()
  internal var held = Array<DarwinSuspension>()
  internal var exceptions: DarwinExceptions?
  internal var ignored = Debuggee.ExceptionMask()
  internal var deferred: Debuggee.Event?
  internal var events = Array<Debuggee.Event>()
  internal var replacement = false
  internal var requested = false
  internal var obsolete = false
  internal var reader: CInt?
  internal var output: Debuggee.Output?
  internal var release = false
}

extension DarwinDebugControl {
  internal mutating func interrupt(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    guard DSX::kill(identifier, SIGSTOP) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    requested = true
    obsolete = false
  }

  internal mutating func collect() -> Debuggee.Event? {
    events.popLast()
  }
}
#endif
