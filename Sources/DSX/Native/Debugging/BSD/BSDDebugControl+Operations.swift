// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc

extension BSDDebugControl {
  // MARK: - Capabilities

  internal static var capabilities: DebugCapabilities {
    .detachment | .passthrough
  }

  internal static var polling: Duration? {
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
      throw Debuggee.Error(unix: errno)
    }
    self.process = process
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    guard ptrace(PT_DETACH, identifier, nil, stopped ? SIGSTOP : 0) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    self = BSDDebugControl()
  }

  internal mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    guard kill(identifier, SIGKILL) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
  }

  // MARK: - Execution

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let process else {
      throw .state
    }
    let threads = try process.threads
    var signal: CInt = 0
    var running = 0
#if os(OpenBSD)
    var selected: ProcessThreadIdentifier?
    var operation: Debuggee.Continuation.Operation = .resume
    var stepping = 0
#endif
    for thread in threads {
      guard let action = actions.action(thread),
          action.operation != .stop else {
        continue
      }
      running += 1
#if os(OpenBSD)
      selected = thread
      operation = action.operation
      if operation == .step {
        stepping += 1
      }
#endif
      if let value = action.signal, value != 0 {
        guard signal == 0 || signal == value else {
          throw .unsupported
        }
        signal = value
      }
    }
    guard running > 0 else {
      return try interrupt(process)
    }
#if os(FreeBSD)
    try prepare(actions)
    for thread in threads {
      let operation = actions.action(thread)?.operation ?? .stop
      let identifier = try thread.native
      let step = operation == .step ? PT_SETSTEP : PT_CLEARSTEP
      guard ptrace(step, identifier, nil, 0) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      let request = operation == .stop ? PT_SUSPEND : PT_RESUME
      guard ptrace(request, identifier, nil, 0) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
    }
    let request = PT_CONTINUE
    let identifier = try process.native
#else
    guard let selected else {
      throw .thread
    }
    // OpenBSD can continue the process, or only its currently trapped thread.
    // It cannot apply an arbitrary mixture of per-thread continuation states.
    let complete = running == threads.count && stepping == 0
    if complete == false {
      guard running == 1, try selected.thread == process.stopped else {
        throw .unsupported
      }
    }
    let identifier = try complete ? process.native : selected.native
    let request = complete || operation == .resume ? PT_CONTINUE : PT_STEP
    try prepare(actions)
#endif
    let address = UnsafeMutablePointer<CChar>(bitPattern: 1)
    guard ptrace(request, identifier, address, signal) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    continuation = (request: request, target: identifier)
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
        throw Debuggee.Error(unix: errno)
      }
    }
    guard let status else {
      return nil
    }
    let thread = try UnixWaitStatus(status).stopped ? process.stopped : nil
    let event = Debuggee.Event(status: status, process: process, thread: thread)
    if case let .stopped(stop) = event, case let .signal(signal) = stop.reason,
        signals.contains(signal), let continuation {
      let address = UnsafeMutablePointer<CChar>(bitPattern: 1)
      guard ptrace(continuation.request, continuation.target, address,
                   signal) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      self.status = nil
      return nil
    }
    self.status = nil
    continuation = nil
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
