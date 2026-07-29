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
    guard threads[native]?.stopped == true else {
      return
    }
    guard ptrace(request(native), native, nil, nil) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    threads[native]?.stopped = false
  }

  internal mutating func interrupt(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.native
    guard self.process == process || children.contains(identifier) else {
      throw .process
    }
    var running = false
    var selected: pid_t?
    for record in threads where record.value.process == process {
      let thread = record.key
      if selected == nil {
        selected = thread
      }
      if threads[thread]?.stopped == true {
        continue
      }
      running = true
    }
    guard running else {
      let candidate =
          threads[identifier]?.stopped == true ? identifier : selected
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
      throw Debuggee.Error(unix: errno)
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
      throw Debuggee.Error(unix: errno)
    }
    var failure: Debuggee.Error?
    for record in threads where record.value.process == process {
      let thread = record.key
      if ptrace(PTRACE_CONT, thread, nil, nil) == 0 {
        threads[thread]?.stopped = false
        continue
      }
      switch errno {
      case ESRCH:
        break
      default:
        if case .none = failure {
          failure = Debuggee.Error(unix: errno)
        }
      }
      threads[thread]?.stopped = false
    }
    if let failure {
      throw failure
    }
  }

  internal mutating func syscalls(_ calls: consuming Array<UInt64>?)
      throws(Debuggee.Error) {
    catches = consume calls
    for index in threads.indices {
      threads.values[index].entry = false
    }
  }

  // MARK: - Execution

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard status == nil else {
      return
    }
    if pending(actions) {
      return
    }
    try prepare(actions)
    if process == nil {
      throw .state
    }
    // Legacy continuation packets may request one process-directed signal.
    // vCont instead carries the signal in each resolved thread action.
    for index in 0 ..< actions.count {
      let action = actions[index]
      if action.operation == .stop {
        continue
      }
      guard action.delivery == .process, let signal = action.signal,
          case .process(let owner) = action.selection else {
        continue
      }
      let identifier = try owner.native
      guard kill(identifier, signal) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
    }
    for index in threads.indices {
      let (thread, state) = threads[index]
      guard state.stopped else {
        continue
      }
      let native = ThreadIdentifier(rawValue: UInt64(thread))
      let owner = state.process
      let identifier = ProcessThreadIdentifier(process: owner, thread: native)
      let planned = actions.action(identifier)
      guard let action = planned else {
        continue
      }
      guard let request: CInt = switch action.operation {
      case .resume:
        if case .some = catches { PTRACE_SYSCALL } else { PTRACE_CONT }
      case .step: PTRACE_SINGLESTEP
      case .stop: nil
      } else {
        continue
      }
      let requested: CInt = switch action.delivery {
      case .thread: action.signal ?? 0
      case .process: 0
      }
      try resume(thread, request: request, signal: requested)
    }
  }

  private mutating func pending(_ actions: borrowing Debuggee.Continuations)
      -> Bool {
    var selected: pid_t?
    for (thread, state) in threads where state.stopped {
      if state.reported || state.signal == nil {
        continue
      }
      let native = ThreadIdentifier(rawValue: UInt64(thread))
      let identifier =
          ProcessThreadIdentifier(process: state.process, thread: native)
      guard let action = actions.action(identifier) else {
        continue
      }
      if action.operation == .stop {
        continue
      }
      selected = if let selected { min(selected, thread) } else { thread }
    }
    guard let selected, let signal = threads[selected]?.signal?.si_signo else {
      return false
    }
    status = UnixWaitStatus(stopped: signal).rawValue
    thread = selected
    threads[selected]?.reported = true
    return true
  }

  internal mutating func resume(_ thread: pid_t, request: CInt, signal: CInt)
      throws(Debuggee.Error) {
    if var pending = threads[thread]?.signal, pending.si_signo == signal {
      let status = withUnsafeMutablePointer(to: &pending) { information in
        ptrace(PTRACE_SETSIGINFO, thread, nil,
               UnsafeMutableRawPointer(information))
      }
      guard status == 0 else {
        throw Debuggee.Error(unix: errno)
      }
    }
    let data = UnsafeMutableRawPointer(bitPattern: Int(signal))
    guard ptrace(request, thread, nil, data) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    threads[thread]?.signal = nil
    threads[thread]?.reported = false
    threads[thread]?.stopped = false
    threads[thread]?.stepping = request == PTRACE_SINGLESTEP
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
    let process = current.process
    for thread in try process.threads {
      let native = try thread.thread.native
      if threads[native] == nil {
        threads[native] = LinuxThreadState(process: process, newborn: true)
      }
    }
    let owner = try process.native
    var interrupted = Set<pid_t>()
    while true {
      // Recheck the barrier: clone and exec change its members, and a ptrace
      // event can resume a thread without completing its stop.
      let pending = threads.compactMap { thread, state in
        state.process == process && (state.pending != nil ||
            state.stopped == false && state.exiting == false) ? thread : nil
      }
      guard !pending.isEmpty else {
        return
      }
      var progressed = false
      for thread in pending {
        guard threads[thread]?.process == process else {
          continue
        }
        if threads[thread]?.pending == nil,
            interrupted.insert(thread).inserted {
          if tgkill(owner, thread, SIGSTOP) < 0 {
            guard errno == ESRCH else {
              throw Debuggee.Error(unix: errno)
            }
          }
        }
        var status: CInt = 0
        let result: pid_t
        if let pending = threads[thread]?.pending {
          status = pending
          result = thread
        } else {
          result = waitpid(thread, &status, __WALL | WNOHANG)
        }
        switch result {
        case thread:
          interrupted.remove(thread)
          progressed = true
          threads[thread]?.pending = status
          try settle(status, thread: thread, process: process)
          threads[thread]?.pending = nil
        case 0:
          break
        default:
          switch errno {
          case EINTR:
            break
          case ECHILD, ESRCH:
            threads.removeValue(forKey: thread)
            interrupted.remove(thread)
            progressed = true
          default:
            throw Debuggee.Error(unix: errno)
          }
        }
      }
      if progressed == false {
        _ = usleep(1_000)
      }
    }
  }

  private mutating func settle(_ status: CInt, thread: pid_t,
                               process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let decoded = UnixWaitStatus(status)
    if let exit = decoded.exit {
      let translated = finish(thread, exit: exit, process: process)
      return try events.append(deliver(translated))
    }
    guard decoded.stopped else {
      throw .state
    }
    if threads[thread]?.newborn == true {
      let identifier = try adopt(thread, process: process)
      return events.append(.started(identifier))
    }
    let code = status >> 16
    if code > 0 {
      if let event = try translate(code, thread: thread, process: process) {
        events.append(event)
        if event.completion {
          threads[thread]?.stopped = true
        }
      }
      return
    }
    let signal = decoded.signal
    if signal == SIGSTOP {
      let generated = try LinuxDebugControl.generated(thread)
      switch generated {
      case false:
        break
      case nil, true:
        threads[thread]?.stopped = true
        return
      }
    }
    let identifier = ThreadIdentifier(rawValue: UInt64(thread))
    let event =
        Debuggee.Event(status: status, process: process, thread: identifier)
    if let translated = try stop(event, signal: signal, thread: thread) {
      events.append(translated)
    }
    threads[thread]?.complete(signal, syscalls: catches != nil)
    threads[thread]?.stopped = true
  }

  internal mutating func collect() -> Debuggee.Event? {
    guard !events.isEmpty else {
      return nil
    }
    return events.removeFirst()
  }

  internal borrowing func request(_ thread: pid_t) -> CInt {
    if threads[thread]?.stepping == true {
      PTRACE_SINGLESTEP
    } else {
      if case .some = catches { PTRACE_SYSCALL } else { PTRACE_CONT }
    }
  }
}
#endif
