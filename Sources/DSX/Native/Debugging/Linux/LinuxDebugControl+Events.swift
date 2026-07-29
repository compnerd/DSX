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
  // MARK: - Events

  internal mutating func event(blocking: Bool = false, output: Bool = true,
                               signals: borrowing SignalSet = SignalSet())
      throws(Debuggee.Error) -> Debuggee.Event? {
    guard let process else {
      throw .state
    }
    if let event = events.popLast() {
      return event
    }
    let launch = configured == false && attached == false
    if output, case .some = self.output {
      return .output(process)
    }
    if case .none = status {
      let token = try token(output: output)
      let event = try wait(token, blocking: blocking)
      try stage(event)
    }
    if output, case .some = self.output {
      return .output(process)
    }
    guard let status, let native = thread else {
      return nil
    }
    self.status = nil
    thread = nil
    let event = ptraceevent(status)
    let thread = ThreadIdentifier(rawValue: UInt64(native))
    let owner = owners[native] ?? process
    let discovered =
        try discover(native, event: event, status: status, process: owner)
    if UnixWaitStatus.stopped(status), newborn.contains(native) || discovered {
      return try .started(adopt(native, process: owner))
    }
    guard case .some = owners[native] else {
      throw .state
    }
    if event > 0 {
      guard let translated =
          try translate(event, thread: native, process: owner) else {
        return nil
      }
      if translated.completion {
        stopped.insert(native)
      }
      return translated
    }
    if try consume(status, thread: native) {
      return nil
    }
    if let exit = UnixWaitStatus.exit(status) {
      let translated = finish(native, exit: exit, process: owner)
      if case .exited(let identifier, _) = translated {
        try depart(identifier)
      }
      return translated
    }
    var translated =
        UnixWaitStatus.event(status, process: owner, thread: thread)
    if UnixWaitStatus.stopped(status),
        UnixWaitStatus.signal(status) == SIGSTOP, requested {
      requested = false
      if obsolete {
        obsolete = false
        guard ptrace(request(native), native, nil, nil) == 0 else {
          throw UnixDebugProcess.failure(errno)
        }
        return nil
      }
      let identifier = ProcessThreadIdentifier(process: owner, thread: thread)
      translated = .stopped(Debuggee.Stop(thread: identifier,
                                          reason: .interrupt))
    }
    if launch, UnixWaitStatus.stopped(status),
        UnixWaitStatus.signal(status) == SIGTRAP {
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      translated =
          .stopped(Debuggee.Stop(thread: identifier, reason: .signal(SIGSTOP)))
    }
    if UnixWaitStatus.stopped(status) {
      let signal = UnixWaitStatus.signal(status)
      switch signal {
      case SIGTRAP | 0x80 where catches != nil:
        let identifier = ProcessThreadIdentifier(process: owner, thread: thread)
        let number = try LinuxRegisters.syscall(identifier)
        let entry = entries.insert(native).inserted
        switch entry {
        case true:
          break
        case false:
          _ = entries.remove(native)
        }
        let selected = catches?.isEmpty == true ||
            catches?.contains(number) == true
        if selected {
          let reason = Debuggee.StopReason.syscall(number, entry)
          translated = .stopped(Debuggee.Stop(thread: identifier,
                                              reason: reason))
        } else {
          guard ptrace(PTRACE_SYSCALL, native, nil, nil) == 0 else {
            throw UnixDebugProcess.failure(errno)
          }
          return nil
        }
      case SIGTRAP:
        let single = stepping.contains(native)
        translated = try LinuxDebugControl.trap(translated, thread: native,
                                                stepping: single)
      case _ where LinuxDebugControl.address(signal):
        translated = try LinuxDebugControl.fault(translated, thread: native)
      default:
        break
      }
    }
    if case .stopped(let stop) = translated,
        case .signal(let signal) = stop.reason, signals.contains(signal),
        launch == false {
      let data = UnsafeMutableRawPointer(bitPattern: Int(signal))
      guard ptrace(request(native), native, nil, data) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      return nil
    }
    if translated.completion {
      if UnixWaitStatus.signal(status) == SIGTRAP {
        _ = stepping.remove(native)
      }
      stopped.insert(native)
      if requested {
        obsolete = true
      }
    }
    if case .exited(let identifier, _) = translated, identifier == process {
      try release()
      reset()
    }
    return translated
  }

  private mutating func consume(_ status: CInt,
                                thread: pid_t) throws(Debuggee.Error) -> Bool {
    if requested {
      return false
    }
    guard UnixWaitStatus.stopped(status),
        UnixWaitStatus.signal(status) == SIGSTOP else {
      return false
    }
    guard let generated = try LinuxDebugControl.generated(thread) else {
      guard ptrace(request(thread), thread, nil, nil) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      _ = stopped.remove(thread)
      return true
    }
    guard generated else {
      return false
    }
    guard ptrace(request(thread), thread, nil, nil) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    _ = stopped.remove(thread)
    return true
  }

  internal static func generated(_ thread: pid_t) throws(Debuggee.Error)
      -> Bool? {
    var information = siginfo_t()
    let result = withUnsafeMutablePointer(to: &information) { information in
      ptrace(PTRACE_GETSIGINFO, thread, nil,
             UnsafeMutableRawPointer(information))
    }
    guard result == 0 else {
      if errno == EINVAL {
        return nil
      }
      throw UnixDebugProcess.failure(errno)
    }
    return information.generated(by: getpid())
  }

  internal static func address(_ signal: CInt) -> Bool {
    signal == SIGBUS || signal == SIGSEGV
  }

  internal static func fault(_ event: Debuggee.Event, thread: pid_t)
      throws(Debuggee.Error) -> Debuggee.Event {
    guard case .stopped(let stop) = event,
        case .signal(let signal) = stop.reason else {
      return event
    }
    let information = try siginfo_t(thread)
    guard information.address(signal) else {
      return event
    }
    let raw = withUnsafePointer(to: information) { information in
      UInt64(dsx_siginfo_address(information))
    }
    let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: raw),
                               code: UInt64(information.si_code),
                               domain: .posix)
    return .stopped(Debuggee.Stop(thread: stop.thread, reason: stop.reason,
                                  core: stop.core, fault: fault,
                                  breakpoint: stop.breakpoint,
                                  child: stop.child, snapshot: stop.snapshot,
                                  chance: stop.chance))
  }

  internal static func trap(_ event: Debuggee.Event, thread: pid_t,
                            stepping: Bool) throws(Debuggee.Error)
      -> Debuggee.Event {
    guard case .stopped(let stop) = event else {
      return event
    }
    let registers = try LinuxGeneralRegisters(thread)
    let information = try siginfo_t(thread)
    let detail = try information.trap(program: ABI.program(registers),
                                      fallback: stop.reason, stepping: stepping)
    let address = Debuggee.Address(rawValue: detail.address)
    let fault = Debuggee.Fault(address: address, domain: .posix)
    return .stopped(Debuggee.Stop(thread: stop.thread, reason: detail.reason,
                                  core: stop.core, fault: fault,
                                  breakpoint: stop.breakpoint,
                                  child: stop.child, snapshot: stop.snapshot,
                                  chance: stop.chance))
  }

  private func token(output: Bool) throws(Debuggee.Error) -> UnixDebugToken {
    if case .some = status {
      return .ready
    }
    if output, case .some = self.output {
      return .ready
    }
    guard let process else {
      throw .state
    }
    let reader = output ? self.reader : nil
    return try .process(process.native, reader)
  }

  private borrowing func wait(_ token: UnixDebugToken, blocking: Bool)
      throws(Debuggee.Error) -> UnixDebugPending {
    guard case .process(_, let reader) = token else {
      return .ready
    }
    while true {
      if let reader {
        var output = Debuggee.Output()
        let count = withUnsafeMutableBytes(of: &output.bytes) { buffer in
          read(reader, buffer.baseAddress, buffer.count)
        }
        switch count {
        case 1...:
          output.count = count
          DSX.log("captured \(count) bytes of debuggee output", level: .trace,
                  channel: .process)
          return .output(output)
        case 0:
          break
        default:
          switch errno {
          case EAGAIN, EWOULDBLOCK, EINTR, EIO:
            break
          default:
            throw UnixDebugProcess.failure(errno)
          }
        }
      }
      for thread in owners.keys {
        var status: CInt = 0
        let result = waitpid(thread, &status, __WALL | WNOHANG)
        switch result {
        case thread:
          return .status(thread, status)
        case 0:
          break
        case -1:
          switch errno {
          case ECHILD, EINTR, ESRCH:
            break
          default:
            throw UnixDebugProcess.failure(errno)
          }
        default:
          throw .state
        }
      }
      guard blocking else {
        return .ready
      }
      _ = usleep(1_000)
    }
  }

  private mutating func stage(_ pending: UnixDebugPending)
      throws(Debuggee.Error) {
    switch pending {
    case .output(let output):
      self.output = output
      return
    case .ready:
      return
    case .status(let thread, let status):
      guard case .some = process else {
        throw .state
      }
      if case (false, true) = (configured, UnixWaitStatus.stopped(status)) {
        try LinuxDebugControl.configure(thread)
        configured = true
      }
      self.status = status
      self.thread = thread
    }
  }

  internal mutating func finish(_ thread: pid_t, exit: Debuggee.Exit,
                                process: ProcessIdentifier) -> Debuggee.Event {
    _ = entries.remove(thread)
    _ = newborn.remove(thread)
    _ = stopped.remove(thread)
    owners.removeValue(forKey: thread)
    _ = stepping.remove(thread)
    if thread == pid_t(process.rawValue) {
      return .exited(process, exit)
    }
    let native = ThreadIdentifier(rawValue: UInt64(thread))
    let identifier = ProcessThreadIdentifier(process: process, thread: native)
    return .terminated(identifier, exit.code)
  }

  // MARK: - Event Translation

  internal mutating func translate(_ event: CInt, thread: pid_t,
                                   process: ProcessIdentifier)
      throws(Debuggee.Error) -> Debuggee.Event? {
    let native = thread
    let thread = ThreadIdentifier(rawValue: UInt64(native))
    let parent = ProcessThreadIdentifier(process: process, thread: thread)
    switch event {
    case PTRACE_EVENT_STOP:
      requested = false
      if obsolete {
        obsolete = false
        guard ptrace(request(native), native, nil, nil) == 0 else {
          throw UnixDebugProcess.failure(errno)
        }
        return nil
      }
      return .stopped(Debuggee.Stop(thread: parent, reason: .interrupt))
    case PTRACE_EVENT_CLONE:
      var message: UInt = 0
      guard ptrace(PTRACE_GETEVENTMSG, native, nil, &message) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      guard message <= UInt(pid_t.max) else {
        throw .thread
      }
      let child = pid_t(message)
      if owners[child] == nil {
        newborn.insert(child)
        owners[child] = process
      }
      guard ptrace(request(native), native, nil, nil) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      return nil
    case PTRACE_EVENT_FORK, PTRACE_EVENT_VFORK:
      var message: UInt = 0
      guard ptrace(PTRACE_GETEVENTMSG, native, nil, &message) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      guard message <= UInt(pid_t.max) else {
        throw .process
      }
      let native = pid_t(message)
      try collect(native)
      children.insert(native)
      let child = ProcessIdentifier(rawValue: UInt64(message))
      stopped.insert(native)
      owners[native] = child
      try LinuxDebugControl.configure(native)
      let thread = ThreadIdentifier(rawValue: child.rawValue)
      let identifier = ProcessThreadIdentifier(process: child, thread: thread)
      return .forked(Debuggee.Fork(parent: parent, child: identifier,
                                   vfork: event == PTRACE_EVENT_VFORK))
    case PTRACE_EVENT_EXEC:
      var message: UInt = 0
      guard ptrace(PTRACE_GETEVENTMSG, native, nil, &message) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      guard message <= UInt(pid_t.max) else {
        throw .thread
      }
      let previous = pid_t(message)
      let owner = owners.removeValue(forKey: previous) ?? process
      switch previous {
      case native:
        break
      default:
        _ = stopped.remove(previous)
        _ = stepping.remove(previous)
        _ = newborn.remove(previous)
      }
      owners[native] = owner
      let identifier = ProcessThreadIdentifier(process: owner, thread: thread)
      return .executed(identifier)
    case PTRACE_EVENT_VFORK_DONE:
      return .stopped(Debuggee.Stop(thread: parent, reason: .vforkdone))
    case PTRACE_EVENT_EXIT:
      guard ptrace(PTRACE_CONT, native, nil, nil) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      return nil
    default:
      return .stopped(Debuggee.Stop(thread: parent,
                                    reason: .exception(UInt64(event))))
    }
  }

  private borrowing func discover(_ thread: pid_t, event: CInt, status: CInt,
                                  process: ProcessIdentifier)
      throws(Debuggee.Error) -> Bool {
    if case .some = owners[thread] {
      return false
    }
    let initial = event == PTRACE_EVENT_STOP ||
        event == 0 && UnixWaitStatus.stopped(status) &&
        UnixWaitStatus.signal(status) == SIGSTOP
    guard initial else {
      return false
    }
    let native = ThreadIdentifier(rawValue: UInt64(thread))
    let identifier = ProcessThreadIdentifier(process: process, thread: native)
    return try identifier.alive
  }

  internal mutating func adopt(_ thread: pid_t, process: ProcessIdentifier)
      throws(Debuggee.Error) -> ProcessThreadIdentifier {
    _ = newborn.remove(thread)
    owners[thread] = process
    try LinuxDebugControl.configure(thread)
    try inherit(process, thread: thread)
    stopped.insert(thread)
    let native = ThreadIdentifier(rawValue: UInt64(thread))
    return ProcessThreadIdentifier(process: process, thread: native)
  }

  internal mutating func collect(_ process: pid_t) throws(Debuggee.Error) {
    var status: CInt = 0
    var result: pid_t
    repeat {
      result = waitpid(process, &status, __WALL)
    } while result < 0 && errno == EINTR
    guard result == process, UnixWaitStatus.stopped(status) else {
      throw result < 0 ? UnixDebugProcess.failure(errno) : .state
    }
  }

}
#endif
