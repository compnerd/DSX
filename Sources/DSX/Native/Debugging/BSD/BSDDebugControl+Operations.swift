// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc

extension BSDDebugControl {
  // MARK: - Capabilities

  internal static var capabilities: DebugCapabilities {
    .detachment | .passthrough
  }

  internal static var interval: Int32? {
    nil
  }

  internal mutating func ignore(_: Debuggee.ExceptionMask)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  // MARK: - Lifecycle

  internal mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.native
    guard ptrace(PT_ATTACH, identifier, nil, 0) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    self.process = process
    attached = true
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    guard ptrace(PT_DETACH, identifier, nil, stopped ? SIGSTOP : 0) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    self = BSDDebugControl()
  }

  internal mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    guard kill(identifier, SIGKILL) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
  }

  // MARK: - Execution

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    try prepare(actions)
    guard let process else {
      throw .state
    }
    var request = PT_CONTINUE
    var signal: CInt = 0
    for index in 0 ..< actions.count {
      let action = actions[index]
      guard action.selection.applies(to: process) else {
        continue
      }
      guard let selected: CInt = switch action.operation {
      case .resume: PT_CONTINUE
      case .step: PT_STEP
      case .stop: nil
      } else {
        return try interrupt(process)
      }
      request = selected
      signal = action.signal ?? 0
      break
    }
    let identifier = try process.native
    let address = UnsafeMutablePointer<CChar>(bitPattern: 1)
    guard ptrace(request, identifier, address, signal) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    self.request = request
  }

  // MARK: - Events

  internal mutating func event(blocking: Bool = false, output: Bool = true,
                               signals: borrowing SignalSet = SignalSet())
      throws(Debuggee.Error) -> Debuggee.Event? {
    guard let process else {
      throw .state
    }
    if case .none = status {
      let identifier = try process.native
      var status: CInt = 0
      var result: pid_t
      repeat {
        result = waitpid(identifier, &status, blocking ? 0 : WNOHANG)
      } while result == -1 && errno == EINTR
      switch result {
      case identifier:
        self.status = status
      case 0:
        break
      default:
        throw UnixDebugProcess.failure(errno)
      }
    }
    guard let status else {
      return nil
    }
    self.status = nil
    let event = UnixWaitStatus.event(status, process: process)
    if case .stopped(let stop) = event, case .signal(let signal) = stop.reason,
        signals.contains(signal), let request {
      let identifier = try process.native
      let address = UnsafeMutablePointer<CChar>(bitPattern: 1)
      guard ptrace(request, identifier, address, signal) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      return nil
    }
    request = nil
    if case .exited = event {
      self = BSDDebugControl()
    }
    return event
  }

  internal mutating func recover() throws(Debuggee.Error) {
    guard let process else {
      return
    }
    try interrupt(process)
  }

  // MARK: - Input and Output

  internal func output(_ process: ProcessIdentifier,
                       into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  internal func input(_ process: ProcessIdentifier,
                      bytes: borrowing Span<UInt8>) throws(Debuggee.Error) {
    throw .unsupported
  }

  // MARK: - Session Services

#if !(os(FreeBSD) && arch(x86_64))
  internal func prepare(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
  }

  internal func breakpoint(_ process: ProcessIdentifier,
                           site: borrowing BreakpointSite,
                           thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  internal func hit(_ stop: borrowing Debuggee.Stop,
                    site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    false
  }
#endif

}
#endif
