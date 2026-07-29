// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

extension LinuxDebugControl {
  internal mutating func discard(_ event: borrowing Debuggee.Event)
      throws(Debuggee.Error) {
    guard let thread: ProcessThreadIdentifier = switch event {
    case .started(let thread): thread
    default: nil
    } else {
      return
    }
    let native = try thread.thread.native
    guard stopped.contains(native) else {
      return
    }
    guard ptrace(request(native), native, nil, nil) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    _ = stopped.remove(native)
  }

  internal mutating func interrupt(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.native
    guard self.process == process || children.contains(identifier) else {
      throw .process
    }
    var running = false
    var selected: pid_t?
    for record in owners where record.value == process {
      let thread = record.key
      if selected == nil {
        selected = thread
      }
      if stopped.contains(thread) {
        continue
      }
      running = true
    }
    guard running else {
      let candidate = stopped.contains(identifier) ? identifier : selected
      guard let native = candidate else {
        throw .state
      }
      let thread = ThreadIdentifier(rawValue: UInt64(native))
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      let stop = Debuggee.Stop(thread: identifier, reason: .interrupt)
      events.append(.stopped(stop))
      requested = false
      obsolete = false
      return
    }
    guard kill(identifier, SIGSTOP) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    requested = true
    obsolete = false
  }

  internal mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.native
    guard self.process == process || children.contains(identifier) else {
      throw .process
    }
    guard kill(identifier, SIGKILL) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    var failure: Debuggee.Error?
    for record in owners where record.value == process {
      let thread = record.key
      if ptrace(PTRACE_CONT, thread, nil, nil) == 0 {
        _ = stopped.remove(thread)
        continue
      }
      switch errno {
      case ESRCH:
        break
      default:
        if case .none = failure {
          failure = UnixDebugProcess.failure(errno)
        }
      }
      _ = stopped.remove(thread)
    }
    if let failure {
      throw failure
    }
  }

  internal mutating func syscalls(_ calls: consuming Array<UInt64>?)
      throws(Debuggee.Error) {
    catches = consume calls
    entries.removeAll(keepingCapacity: true)
  }

  // MARK: - Execution

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard status == nil else {
      return
    }
    try prepare(actions)
    guard let process else {
      throw .state
    }
    stepping.removeAll(keepingCapacity: true)
    var applied = false
    let stopped = self.stopped
    let fallback =
        try Debuggee.Continuation.Plan.fallback(process, actions: actions)
    if let fallback, let signal = fallback.signal {
      switch fallback.operation {
      case .resume, .step:
        let identifier = try process.native
        guard kill(identifier, signal) == 0 else {
          throw UnixDebugProcess.failure(errno)
        }
      case .stop:
        break
      }
    }
    for thread in stopped {
      let native = ThreadIdentifier(rawValue: UInt64(thread))
      let owner = owners[thread] ?? process
      let identifier = ProcessThreadIdentifier(process: owner, thread: native)
      let planned =
          try Debuggee.Continuation.Plan.resolve(identifier, actions: actions)
      guard let action = planned else {
        continue
      }
      if action.operation == .step {
        stepping.insert(thread)
      }
      guard let request: CInt = switch action.operation {
      case .resume:
        if case .some = catches { PTRACE_SYSCALL } else { PTRACE_CONT }
      case .step: PTRACE_SINGLESTEP
      case .stop: nil
      } else {
        continue
      }
      let signal: CInt = switch action.selection {
      case .thread: action.signal ?? 0
      case .all, .any, .process: 0
      }
      let data = UnsafeMutableRawPointer(bitPattern: Int(signal))
      guard ptrace(request, thread, nil, data) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      _ = self.stopped.remove(thread)
      applied = true
    }
    guard applied else {
      guard stopped.isEmpty else {
        return
      }
      let identifier = try process.native
      let request = if case .some = catches {
        PTRACE_SYSCALL
      } else {
        PTRACE_CONT
      }
      guard ptrace(request, identifier, nil, nil) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      return
    }
  }

  // MARK: - Input and Output

  internal mutating func output(_ process: ProcessIdentifier,
                                into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let count = try forward(process, current: self.process,
                            pending: &self.output, into: &output)
    DSX.log("forwarding \(count) bytes of debuggee output", level: .trace,
            channel: .process)
  }

  internal func input(_ process: ProcessIdentifier,
                      bytes: borrowing Span<UInt8>) throws(Debuggee.Error) {
    guard self.process == process, let reader else {
      throw .state
    }
    try write(reader, bytes: bytes)
  }

  // MARK: - Recovery

  internal mutating func recover() throws(Debuggee.Error) {
    guard let process else {
      return
    }
    try interrupt(process)
  }

  internal mutating func complete(_ event: borrowing Debuggee.Event)
      throws(Debuggee.Error) {
    guard let current: ProcessThreadIdentifier = switch event {
    case .executed(let thread):
      thread
    case .forked(let fork):
      fork.parent
    case .stopped(let stop):
      stop.thread
    case .exited, .image, .output, .started, .terminated:
      nil
    } else {
      return
    }
    let threads = try current.process.threads
    var pending = Array<pid_t>()
    for thread in threads {
      let identifier = try thread.thread.native
      if stopped.contains(identifier) {
        continue
      }
      pending.append(identifier)
    }
    guard !pending.isEmpty else {
      return
    }
    var interrupted = Array<pid_t>()
    let process = try current.process.native
    for thread in pending {
      if tgkill(process, thread, SIGSTOP) == 0 {
        interrupted.append(thread)
      } else {
        guard errno == ESRCH else {
          throw UnixDebugProcess.failure(errno)
        }
      }
    }
    for thread in interrupted {
      var status: CInt = 0
      var result: pid_t
      repeat {
        result = waitpid(thread, &status, __WALL)
      } while result < 0 && errno == EINTR
      if result < 0, errno == ECHILD || errno == ESRCH {
        continue
      }
      guard result == thread else {
        throw .state
      }
      if let exit = UnixWaitStatus.exit(status) {
        let translated = finish(thread, exit: exit, process: current.process)
        if case .exited(let process, _) = translated {
          try depart(process)
          return events.append(translated)
        }
        events.append(translated)
        continue
      }
      guard UnixWaitStatus.stopped(status) else {
        throw .state
      }
      if newborn.contains(thread) {
        let identifier = try adopt(thread, process: current.process)
        events.append(.started(identifier))
        continue
      }
      let code = ptraceevent(status)
      if code > 0 {
        if let event = try translate(code, thread: thread,
                                     process: current.process) {
          events.append(event)
          if event.completion {
            stopped.insert(thread)
          }
        }
        continue
      }
      let signal = UnixWaitStatus.signal(status)
      if signal == SIGSTOP {
        let generated = try LinuxDebugControl.generated(thread)
        switch generated {
        case false:
          break
        case nil, true:
          stopped.insert(thread)
          continue
        }
      }
      let identifier = ThreadIdentifier(rawValue: UInt64(thread))
      let event = UnixWaitStatus.event(status, process: current.process,
                                       thread: identifier)
      let translated = switch signal {
      case SIGTRAP:
        try LinuxDebugControl.trap(event, thread: thread, stepping: false)
      case _ where LinuxDebugControl.address(signal):
        try LinuxDebugControl.fault(event, thread: thread)
      default:
        event
      }
      events.append(translated)
      stopped.insert(thread)
    }
  }

  internal mutating func collect() -> Debuggee.Event? {
    events.popLast()
  }

  internal borrowing func request(_ thread: pid_t) -> CInt {
    if stepping.contains(thread) {
      PTRACE_SINGLESTEP
    } else {
      if case .some = catches { PTRACE_SYSCALL } else { PTRACE_CONT }
    }
  }


}
#endif
