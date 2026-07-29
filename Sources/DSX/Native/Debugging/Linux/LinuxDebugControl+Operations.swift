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
  // MARK: - Capabilities

  internal static var capabilities: DebugCapabilities {
    .allocation | .auxiliary | .detachment | .executable | .fork
        | .passthrough | .randomization | .signal | .svr4 | .syscalls
        | .threads | .vfork
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
    let leader = try process.native
    var traced = Array<pid_t>()
    do throws(Debuggee.Error) {
      for identifier in try process.threads {
        let thread = try identifier.thread.native
        guard ptrace(PTRACE_ATTACH, thread, nil, nil) == 0 else {
          if errno == ESRCH {
            continue
          }
          throw UnixDebugProcess.failure(errno)
        }
        traced.append(thread)
        var status: CInt = 0
        var result: pid_t
        repeat {
          result = waitpid(thread, &status, __WALL)
        } while result < 0 && errno == EINTR
        guard result == thread, UnixWaitStatus.stopped(status) else {
          throw result < 0 ? UnixDebugProcess.failure(errno) : .state
        }
        try LinuxDebugControl.configure(thread)
        stopped.insert(thread)
      }
      guard traced.contains(leader) else {
        throw .process
      }
    } catch {
      for thread in traced {
        _ = ptrace(PTRACE_DETACH, thread, nil, nil)
        _ = stopped.remove(thread)
      }
      throw error
    }
    self.process = process
    attached = true
    configured = true
    for thread in traced {
      owners[thread] = process
    }
    let thread = ThreadIdentifier(rawValue: UInt64(leader))
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    let stop = Debuggee.Stop(thread: identifier, reason: .signal(SIGSTOP))
    events.append(.stopped(stop))
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let identifier = try process.native
    if self.process == process {
      switch stopped {
      case true:
        break
      case false:
        _ = kill(identifier, SIGCONT)
      }
      if children.isEmpty {
        let failure = release(stopped: stopped)
        reset()
        if let failure {
          throw failure
        }
      } else {
        let failure = release(process, stopped: stopped)
        promote()
        if let failure {
          throw failure
        }
      }
    } else {
      guard children.contains(identifier) else {
        throw .process
      }
      if let failure = release(process, stopped: stopped) {
        throw failure
      }
    }
  }

  internal mutating func discard(_ fork: borrowing Debuggee.Fork)
      throws(Debuggee.Error) {
    let parent = try fork.parent.process.native
    guard process == fork.parent.process || children.contains(parent) else {
      throw .process
    }
    let child = try fork.child.process.native
    guard children.contains(child) else {
      throw .process
    }
    if let failure = release(fork.child.process, stopped: false) {
      throw failure
    }
  }

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

  private static func generated(_ thread: pid_t) throws(Debuggee.Error)
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
    guard information.si_code == SI_USER || information.si_code == SI_TKILL,
        dsx_siginfo_sender(&information) == getpid() else {
      return false
    }
    return true
  }

  private static func address(_ signal: CInt) -> Bool {
    signal == SIGBUS || signal == SIGSEGV
  }

  private static func address(_ signal: CInt, code: CInt) -> Bool {
    switch signal {
    case SIGBUS:
      return code >= kBUS_ADRALN && code <= kBUS_OBJERR
    case SIGSEGV:
      let standard = code >= kSEGV_MAPERR && code <= kSEGV_PKUERR
      return standard || code == kSEGV_MTESERR || code == SI_KERNEL
    default:
      return false
    }
  }

  private static func fault(_ event: Debuggee.Event, thread: pid_t)
      throws(Debuggee.Error) -> Debuggee.Event {
    guard case .stopped(let stop) = event,
        case .signal(let signal) = stop.reason else {
      return event
    }
    var information = siginfo_t()
    let status = withUnsafeMutablePointer(to: &information) { information in
      ptrace(PTRACE_GETSIGINFO, thread, nil,
             UnsafeMutableRawPointer(information))
    }
    guard status == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    guard address(signal, code: information.si_code) else {
      return event
    }
    let raw = UInt64(dsx_siginfo_address(&information))
    let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: raw),
                               code: UInt64(information.si_code),
                               domain: .posix)
    return .stopped(Debuggee.Stop(thread: stop.thread, reason: stop.reason,
                                  core: stop.core, fault: fault,
                                  breakpoint: stop.breakpoint,
                                  child: stop.child, snapshot: stop.snapshot,
                                  chance: stop.chance))
  }

  private static func trap(_ event: Debuggee.Event, thread: pid_t,
                           stepping: Bool) throws(Debuggee.Error)
      -> Debuggee.Event {
    guard case .stopped(let stop) = event else {
      return event
    }
    var registers = LinuxGeneralRegisters()
    var vector =
        iovec(iov_base: nil,
              iov_len: numericCast(MemoryLayout<LinuxGeneralRegisters>.size))
    let result = withUnsafeMutablePointer(to: &registers) { registers in
      vector.iov_base = UnsafeMutableRawPointer(registers)
      return withUnsafeMutablePointer(to: &vector) { vector in
        ptrace(PTRACE_GETREGSET, thread,
               UnsafeMutableRawPointer(bitPattern: NT_PRSTATUS),
               UnsafeMutableRawPointer(vector))
      }
    }
    let complete =
        vector.iov_len == numericCast(MemoryLayout<LinuxGeneralRegisters>.size)
    guard result == 0, complete else {
      throw result == 0 ? .register : UnixDebugProcess.failure(errno)
    }
    var information = siginfo_t()
    let status = withUnsafeMutablePointer(to: &information) { information in
      ptrace(PTRACE_GETSIGINFO, thread, nil,
             UnsafeMutableRawPointer(information))
    }
    guard status == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    let detail = try LinuxDebugControl.trap(information.si_code,
                                            program: ABI.program(registers),
                                            fallback: stop.reason,
                                            stepping: stepping)
    let address = if information.si_code == TRAP_HWBKPT {
      UInt64(dsx_siginfo_address(&information))
    } else {
      detail.address
    }
    let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: address),
                               domain: .posix)
    return .stopped(Debuggee.Stop(thread: stop.thread, reason: detail.reason,
                                  core: stop.core, fault: fault,
                                  breakpoint: stop.breakpoint,
                                  child: stop.child, snapshot: stop.snapshot,
                                  chance: stop.chance))
  }

  internal static func trap(_ code: CInt, program: UInt64,
                            fallback: Debuggee.StopReason,
                            stepping: Bool = false) throws(Debuggee.Error)
      -> (address: UInt64, reason: Debuggee.StopReason) {
    if code == SI_KERNEL || code == TRAP_BRKPT {
      try (ABI.breakpoint(program), .breakpoint)
    } else {
      switch code {
      case ...0: (program, stepping ? .trace : .signal(SIGTRAP))
      case TRAP_TRACE: (program, .trace)
      default: (program, fallback)
      }
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

  private mutating func finish(_ thread: pid_t, exit: Debuggee.Exit,
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

  internal mutating func close() throws(Debuggee.Error) {
    guard case .some = process else {
      return
    }
    let failure = release(stopped: false)
    reset()
    if let failure {
      throw failure
    }
  }

  // MARK: - Cleanup

  private static func detach(_ process: pid_t,
                             stopped: Bool) throws(Debuggee.Error) {
    let signal = UnsafeMutableRawPointer(bitPattern: stopped ? Int(SIGSTOP) : 0)
    guard ptrace(PTRACE_DETACH, process, nil, signal) == 0 else {
      guard errno == ESRCH else {
        throw UnixDebugProcess.failure(errno)
      }
      return
    }
  }

  private mutating func release() throws(Debuggee.Error) {
    if let failure = release(stopped: false) {
      throw failure
    }
  }

  private mutating func release(stopped: Bool) -> Debuggee.Error? {
    var failure: Debuggee.Error?
    for thread in owners.keys {
      do throws(Debuggee.Error) {
        try LinuxDebugControl.detach(thread, stopped: stopped)
      } catch {
        if case .none = failure {
          failure = error
        }
      }
    }
    children.removeAll(keepingCapacity: true)
    self.stopped.removeAll(keepingCapacity: true)
    stepping.removeAll(keepingCapacity: true)
    owners.removeAll(keepingCapacity: true)
    return failure
  }

  private mutating func release(_ process: ProcessIdentifier, stopped: Bool)
      -> Debuggee.Error? {
    var failure: Debuggee.Error?
    for record in owners where record.value == process {
      let thread = record.key
      do throws(Debuggee.Error) {
        try LinuxDebugControl.detach(thread, stopped: stopped)
      } catch {
        if case .none = failure {
          failure = error
        }
      }
    }
    if let thread, owners[thread] == process {
      status = nil
      self.thread = nil
    }
    events.removeAll { event in
      event.process == process
    }
    for record in owners where record.value == process {
      _ = entries.remove(record.key)
      _ = newborn.remove(record.key)
      _ = self.stopped.remove(record.key)
      _ = stepping.remove(record.key)
    }
    while let thread = owners.first(where: { $0.value == process })?.key {
      owners.removeValue(forKey: thread)
    }
    _ = children.remove(pid_t(process.rawValue))
    return failure
  }

  private mutating func depart(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    if self.process == process {
      if children.isEmpty {
        try release()
        reset()
      } else {
        promote()
      }
    } else {
      _ = children.remove(pid_t(process.rawValue))
    }
  }

  private mutating func promote() {
    guard let child = children.first else {
      return
    }
    _ = children.remove(child)
    process = ProcessIdentifier(rawValue: UInt64(child))
  }

  private static func configure(_ process: pid_t) throws(Debuggee.Error) {
    let options = UnsafeMutableRawPointer(bitPattern: LinuxDebugControl.options)
    guard ptrace(PTRACE_SETOPTIONS, process, nil, options) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
  }

  private static var options: UInt {
    PTRACE_O_TRACESYSGOOD | PTRACE_O_TRACEFORK | PTRACE_O_TRACEVFORK
        | PTRACE_O_TRACECLONE | PTRACE_O_TRACEEXEC | PTRACE_O_TRACEVFORKDONE
        | PTRACE_O_TRACEEXIT
  }

  private mutating func reset() {
    if let reader {
      _ = DSX::close(reader)
    }
    self = LinuxDebugControl()
  }

  // MARK: - Event Translation

  private mutating func translate(_ event: CInt, thread: pid_t,
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

  private borrowing func request(_ thread: pid_t) -> CInt {
    if stepping.contains(thread) {
      PTRACE_SINGLESTEP
    } else {
      if case .some = catches { PTRACE_SYSCALL } else { PTRACE_CONT }
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

  private mutating func adopt(_ thread: pid_t, process: ProcessIdentifier)
      throws(Debuggee.Error) -> ProcessThreadIdentifier {
    _ = newborn.remove(thread)
    owners[thread] = process
    try LinuxDebugControl.configure(thread)
    try inherit(process, thread: thread)
    stopped.insert(thread)
    let native = ThreadIdentifier(rawValue: UInt64(thread))
    return ProcessThreadIdentifier(process: process, thread: native)
  }

  private mutating func collect(_ process: pid_t) throws(Debuggee.Error) {
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
