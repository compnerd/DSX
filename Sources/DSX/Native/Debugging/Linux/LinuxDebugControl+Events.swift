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
    if let deferred {
      return try deliver(deferred)
    }
    guard let process else {
      throw .state
    }
    if let event = collect() {
      return event
    }
    let launch = configured == false && attached == false
    if output, case .some = self.output {
      return .output(process)
    }
    if case .none = status {
      try wait(output ? reader : nil, blocking: blocking)
    }
    if output, case .some = self.output {
      return .output(process)
    }
    guard let status, let native = thread else {
      return nil
    }
    let decoded = UnixWaitStatus(status)
    if configured == false, decoded.stopped {
      try LinuxDebugControl.configure(native)
    }
    let event = try receive(status, thread: native, process: process,
                            launch: launch, signals: signals)
    self.status = nil
    thread = nil
    if decoded.stopped {
      configured = true
      if status >> 16 == 0 {
        threads[native]?.complete(decoded.signal, syscalls: catches != nil)
      }
    }
    guard let event else {
      return nil
    }
    return try deliver(event)
  }

  internal mutating func deliver(_ event: Debuggee.Event)
      throws(Debuggee.Error) -> Debuggee.Event {
    if case .exited(let process, _) = event {
      do throws(Debuggee.Error) {
        try depart(process)
      } catch {
        deferred = event
        throw error
      }
    }
    deferred = nil
    return event
  }

  private mutating func receive(_ status: CInt, thread native: pid_t,
                                process: ProcessIdentifier, launch: Bool,
                                signals: borrowing SignalSet)
      throws(Debuggee.Error) -> Debuggee.Event? {
    let decoded = UnixWaitStatus(status)
    let event = status >> 16
    let thread = ThreadIdentifier(rawValue: UInt64(native))
    let owner = threads[native]?.process ?? process
    let discovered =
        try discover(native, event: event, status: status, process: owner)
    if decoded.stopped, threads[native]?.newborn == true || discovered {
      return try .started(adopt(native, process: owner))
    }
    guard case .some = threads[native] else {
      throw .state
    }
    if event > 0 {
      guard let translated =
          try translate(event, thread: native, process: owner) else {
        return nil
      }
      if translated.completion {
        threads[native]?.stopped = true
      }
      return translated
    }
    if try consume(status, thread: native) {
      return nil
    }
    if let exit = decoded.exit {
      return finish(native, exit: exit, process: owner)
    }
    var translated =
        Debuggee.Event(status: status, process: owner, thread: thread)
    if decoded.stopped, decoded.signal == SIGSTOP, requested {
      if obsolete {
        guard ptrace(request(native), native, nil, nil) == 0 else {
          throw Debuggee.Error(unix: errno)
        }
        requested = false
        obsolete = false
        return nil
      }
      let identifier = ProcessThreadIdentifier(process: owner, thread: thread)
      translated =
          .stopped(Debuggee.Stop(thread: identifier, reason: .interrupt))
    }
    if launch, decoded.stopped, decoded.signal == SIGTRAP {
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      translated =
          .stopped(Debuggee.Stop(thread: identifier, reason: .signal(SIGSTOP)))
    }
    if decoded.stopped {
      guard let stop =
          try stop(translated, signal: decoded.signal, thread: native) else {
        guard ptrace(PTRACE_SYSCALL, native, nil, nil) == 0 else {
          throw Debuggee.Error(unix: errno)
        }
        return nil
      }
      translated = stop
    }
    if case .stopped(let stop) = translated,
        case .signal(let signal) = stop.reason, signals.contains(signal),
        launch == false {
      try resume(native, request: request(native), signal: signal)
      return nil
    }
    if translated.completion {
      threads[native]?.stopped = true
      switch translated {
      case .stopped(let stop) where stop.reason == .interrupt:
        requested = false
      default:
        if requested {
          obsolete = true
        }
      }
    }
    return translated
  }

  /// Interprets a stop without deciding whether the thread should resume.
  internal func stop(_ event: Debuggee.Event, signal: CInt, thread: pid_t)
      throws(Debuggee.Error) -> Debuggee.Event? {
    switch signal {
    case SIGTRAP | 0x80 where catches != nil:
      let failure = Debuggee.Error.init(register:)
      let registers = try LinuxGeneralRegisters(thread, failure: failure)
      let number = registers.syscall
      let entry = threads[thread]?.entry == false
      guard catches?.isEmpty == true || catches?.contains(number) == true else {
        return nil
      }
      guard case .stopped(let stop) = event else {
        throw .state
      }
      let reason = Debuggee.StopReason.syscall(number, entry)
      return .stopped(stop.refined(reason: reason, fault: stop.fault,
                                   breakpoint: stop.breakpoint))
    case SIGTRAP:
      let stepping = threads[thread]?.stepping == true
      return try event.trap(thread, stepping: stepping)
    case SIGBUS, SIGSEGV:
      return try event.fault(thread)
    default:
      return event
    }
  }

  private mutating func consume(_ status: CInt,
                                thread: pid_t) throws(Debuggee.Error) -> Bool {
    if requested {
      return false
    }
    let decoded = UnixWaitStatus(status)
    guard decoded.stopped, decoded.signal == SIGSTOP else {
      return false
    }
    guard let generated = try LinuxDebugControl.generated(thread) else {
      guard ptrace(request(thread), thread, nil, nil) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      threads[thread]?.stopped = false
      return true
    }
    guard generated else {
      return false
    }
    guard ptrace(request(thread), thread, nil, nil) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    threads[thread]?.stopped = false
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
      throw Debuggee.Error(unix: errno)
    }
    return information.generated(by: getpid())
  }

  private mutating func wait(_ reader: CInt?, blocking: Bool)
      throws(Debuggee.Error) {
    while true {
      if let output = try Debuggee.Output(reader) {
        DSX.log("captured \(output.count) bytes of debuggee output",
                level: .trace, channel: .process)
        self.output = output
        return
      }
      for thread in threads.keys {
        if let pending = threads[thread]?.pending {
          self.status = pending
          self.thread = thread
          threads[thread]?.pending = nil
          return
        }
        var status: CInt = 0
        let result = waitpid(thread, &status, __WALL | WNOHANG)
        switch result {
        case thread:
          self.status = status
          self.thread = thread
          return
        case 0:
          break
        case -1:
          switch errno {
          case ECHILD, EINTR, ESRCH:
            break
          default:
            throw Debuggee.Error(unix: errno)
          }
        default:
          throw .state
        }
      }
      guard blocking else {
        return
      }
      _ = usleep(1_000)
    }
  }

  internal mutating func finish(_ thread: pid_t, exit: Debuggee.Exit,
                                process: ProcessIdentifier) -> Debuggee.Event {
    threads.removeValue(forKey: thread)
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
      if obsolete {
        guard ptrace(request(native), native, nil, nil) == 0 else {
          throw Debuggee.Error(unix: errno)
        }
        requested = false
        obsolete = false
        return nil
      }
      requested = false
      return .stopped(Debuggee.Stop(thread: parent, reason: .interrupt))
    case PTRACE_EVENT_CLONE:
      var message: UInt = 0
      guard ptrace(PTRACE_GETEVENTMSG, native, nil, &message) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      guard message <= UInt(pid_t.max) else {
        throw .thread
      }
      let child = pid_t(message)
      if threads[child] == nil {
        threads[child] = LinuxThreadState(process: process, newborn: true)
      }
      guard ptrace(request(native), native, nil, nil) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      return nil
    case PTRACE_EVENT_FORK, PTRACE_EVENT_VFORK:
      var message: UInt = 0
      guard ptrace(PTRACE_GETEVENTMSG, native, nil, &message) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      guard message <= UInt(pid_t.max) else {
        throw .process
      }
      let native = pid_t(message)
      let child = ProcessIdentifier(rawValue: UInt64(message))
      if children.contains(native) == false {
        try collect(native)
        children.insert(native)
        threads[native] = LinuxThreadState(process: child, stopped: true)
      }
      try LinuxDebugControl.configure(native)
      let thread = ThreadIdentifier(rawValue: child.rawValue)
      let identifier = ProcessThreadIdentifier(process: child, thread: thread)
      return .forked(Debuggee.Fork(parent: parent, child: identifier,
                                   vfork: event == PTRACE_EVENT_VFORK))
    case PTRACE_EVENT_EXEC:
      var message: UInt = 0
      guard ptrace(PTRACE_GETEVENTMSG, native, nil, &message) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      guard message <= UInt(pid_t.max) else {
        throw .thread
      }
      let previous = pid_t(message)
      var state = threads.removeValue(forKey: previous)
          ?? LinuxThreadState(process: process)
      if previous != native {
        state.stopped = false
        state.stepping = false
        state.newborn = false
        state.entry = false
      }
      let owner = state.process
      threads[native] = state
      let identifier = ProcessThreadIdentifier(process: owner, thread: thread)
      return .executed(identifier)
    case PTRACE_EVENT_VFORK_DONE:
      return .stopped(Debuggee.Stop(thread: parent, reason: .vforkdone))
    case PTRACE_EVENT_EXIT:
      guard ptrace(PTRACE_CONT, native, nil, nil) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      // A group leader can remain a zombie until its last thread exits. Keep
      // collecting its final status, but do not wait for it to stop again.
      threads[native]?.exiting = true
      return nil
    default:
      return .stopped(Debuggee.Stop(thread: parent,
                                    reason: .exception(UInt64(event))))
    }
  }

  private borrowing func discover(_ thread: pid_t, event: CInt, status: CInt,
                                  process: ProcessIdentifier)
      throws(Debuggee.Error) -> Bool {
    if case .some = threads[thread] {
      return false
    }
    let initial = event == PTRACE_EVENT_STOP ||
        event == 0 && UnixWaitStatus(status).stopped &&
        UnixWaitStatus(status).signal == SIGSTOP
    guard initial else {
      return false
    }
    let native = ThreadIdentifier(rawValue: UInt64(thread))
    let identifier = ProcessThreadIdentifier(process: process, thread: native)
    return try identifier.alive
  }

  internal mutating func adopt(_ thread: pid_t, process: ProcessIdentifier)
      throws(Debuggee.Error) -> ProcessThreadIdentifier {
    if threads[thread] == nil {
      threads[thread] = LinuxThreadState(process: process, newborn: true)
    }
    threads[thread]?.process = process
    try LinuxDebugControl.configure(thread)
    try inherit(process, thread: thread)
    threads[thread]?.newborn = false
    threads[thread]?.stopped = true
    let native = ThreadIdentifier(rawValue: UInt64(thread))
    return ProcessThreadIdentifier(process: process, thread: native)
  }

  @discardableResult
  internal mutating func collect(_ process: pid_t) throws(Debuggee.Error)
      -> CInt {
    var status: CInt = 0
    var result: pid_t
    repeat {
      result = waitpid(process, &status, __WALL)
    } while result < 0 && errno == EINTR
    guard result == process, UnixWaitStatus(status).stopped else {
      throw result < 0 ? Debuggee.Error(unix: errno) : .state
    }
    return status
  }
}
#endif
