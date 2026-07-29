// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims

extension DarwinDebugControl {
  // MARK: - Capabilities

  internal static var capabilities: DebugCapabilities {
    .allocation | .detachment | .executable | .images | .libraries
        | .randomization
  }

  internal static var interval: Int32? {
    1
  }

  // MARK: - Lifecycle

  internal mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.native
    let release = suspended(identifier)
    let exceptions = try DarwinExceptions(process, ignored: ignored)
    var denied: CInt = 0
    guard ptrace(identifier, denied: &denied) == 0 else {
      if denied == 1 {
        throw .denied
      }
      throw UnixDebugProcess.failure(errno)
    }
    self.process = process
    attached = true
    self.release = release
    self.exceptions = exceptions
  }

  internal mutating func ignore(_ exceptions: Debuggee.ExceptionMask)
      throws(Debuggee.Error) {
    guard process == nil else {
      throw .state
    }
    ignored = exceptions
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    guard kill(identifier, SIGSTOP) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    if let exceptions, exceptions.pending {
      try exceptions.reply()
    }
    exceptions = nil
    if suspended(identifier) == false {
      var status: CInt = 0
      var waited: pid_t
      repeat {
        waited = waitpid(identifier, &status, 0)
      } while waited == -1 && errno == EINTR
      guard waited == identifier, UnixWaitStatus.stopped(status),
          UnixWaitStatus.signal(status) == SIGSTOP else {
        throw UnixDebugProcess.failure(errno)
      }
    }
    let address = UnsafeMutablePointer<CChar>(bitPattern: 1)
    let detached = ptrace(kPTDetach, identifier, address, 0)
    let code = errno
    guard detached == 0 else {
      throw UnixDebugProcess.failure(code)
    }
    if stopped {
      guard kill(identifier, SIGSTOP) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
    }
    self.process = nil
    attached = false
    discard()
  }

  internal mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    let exception: DarwinExceptions? = if let exceptions, exceptions.pending {
      exceptions
    } else {
      nil
    }
    if let exception {
      try exception.reply()
    }
    let status = ptrace(kPTKill, identifier, nil, 0)
    if let exception {
      try exception.resume()
    }
    guard status == 0 else {
      guard kill(identifier, SIGKILL) == 0 || errno == ESRCH else {
        throw UnixDebugProcess.failure(errno)
      }
      return
    }
  }

  // MARK: - Execution

  internal mutating func prepare(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let process, !breakpoints.isEmpty else {
      return
    }
    let threads = try DarwinThreadList(process)
    try configure(threads)
  }

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let process else {
      throw .state
    }
    if requested, obsolete {
      let identifier = try process.native
      guard kill(identifier, SIGCONT) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      requested = false
      obsolete = false
    }
    let threads = try DarwinThreadList(process)
    try configure(threads)
    let plan = try plan(actions, process: process, threads: threads)
    if plan.interrupt {
      return try interrupt(process)
    }
    try hold(actions, process: process, threads: threads)
    let replacement = self.replacement
    self.replacement = false
    let signal = replacement ? 0 : plan.signal
    if let exceptions, exceptions.pending {
      if replacement, plan.signal != 0 {
        let identifier = try process.native
        guard kill(identifier, plan.signal) == 0 else {
          throw UnixDebugProcess.failure(errno)
        }
      }
      try exceptions.reply(signal)
      do throws(Debuggee.Error) {
        try step(actions, process: process, threads: threads)
      } catch {
        try? exceptions.resume()
        throw error
      }
      return try exceptions.resume()
    }
    try step(actions, process: process, threads: threads)
    let identifier = try process.native
    let address = UnsafeMutablePointer<CChar>(bitPattern: 1)
    guard ptrace(plan.request, identifier, address, signal) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    _ = awaken(identifier)
    if release {
      release = false
      _ = kill(identifier, SIGCONT)
    }
    if replacement, plan.signal != 0 {
      guard kill(identifier, plan.signal) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
    }
  }

  // MARK: - Events

  internal mutating func event(blocking: Bool = false, output: Bool = true,
                               signals _: borrowing SignalSet = SignalSet())
      throws(Debuggee.Error) -> Debuggee.Event? {
    guard let process else {
      throw .state
    }
    if output, case .some = self.output {
      return .output(process)
    }
    if let deferred {
      if output {
        try stage(sample(reader))
        if case .some = self.output {
          return .output(process)
        }
      }
      self.deferred = nil
      return deliver(deferred)
    }
    while true {
      if let exceptions, let record = try exceptions.next() {
        guard try exceptions.accept(record, process: process) else {
          DSX.log("rejecting foreign Darwin exception", level: .trace,
                  channel: .process)
          try exceptions.reject()
          continue
        }
        while let record = try exceptions.receive() {
          guard try exceptions.accept(record, process: process) else {
            DSX.log("rejecting foreign Darwin exception", level: .trace,
                    channel: .process)
            try exceptions.reject()
            continue
          }
        }
        var stepping: ThreadIdentifier?
        for index in 0 ..< exceptions.count {
          let thread = try identity(exceptions[index].thread)
          if steps.contains(where: { candidate in
            candidate.thread == thread
          }) {
            stepping = thread
            break
          }
        }
        let threads = try DarwinThreadList(process)
        try finish(threads)
        try restore(process, threads: threads)
        guard events.isEmpty else {
          throw .state
        }
        var selected = 0
        var priority = Int.min
        var replacement = false
        var stale = true
        let waiting = requested
        var signalled = false
        for index in 0 ..< exceptions.count {
          let record = exceptions[index]
          let message = "Darwin exception \(record.type) on Mach thread " +
              "\(record.thread): \(record.codes.0), \(record.codes.1)"
          DSX.log(message, level: .trace, channel: .process)
          let interrupt = waiting && interrupted(record)
          if interrupt {
            requested = false
            signalled = true
          }
          if interrupt && obsolete {
            continue
          }
          stale = false
          let event = if interrupt {
            try interruption(record, process: process)
          } else {
            try translate(record, process: process, threads: threads,
                          breakpoints: breakpoints)
          }
          let candidate = switch event {
          case .stopped(let stop) where stop.thread.thread == stepping:
            2
          case .stopped where !interrupt:
            1
          default:
            0
          }
          if candidate > priority {
            selected = events.count
            priority = candidate
            replacement = interrupt
          }
          events.append(event)
        }
        if signalled && obsolete {
          obsolete = false
        }
        if stale {
          try exceptions.reply()
          try exceptions.resume()
          continue
        }
        let event = events.remove(at: selected)
        self.replacement = replacement
        if event.completion, requested {
          obsolete = true
        }
        return try enqueue(event, process: process, output: output)
      }
      if case .none = status {
        let pending = try wait(process, reader: output ? reader : nil)
        try stage(pending)
      }
      if output, case .some = self.output {
        return .output(process)
      }
      guard let status else {
        if blocking {
          _ = usleep(1_000)
          continue
        }
        return nil
      }
      self.status = nil
      if UnixWaitStatus.stopped(status) {
        continue
      }
      let event = UnixWaitStatus.event(status, process: process)
      if event.completion, requested {
        obsolete = true
      }
      return try enqueue(event, process: process, output: output)
    }
  }

  internal mutating func recover() throws(Debuggee.Error) {
    guard let process else {
      return
    }
    try restore(process)
    let identifier = try process.native
    guard kill(identifier, SIGSTOP) == 0 || errno == ESRCH else {
      throw UnixDebugProcess.failure(errno)
    }
  }

  // MARK: - Input and Output

  internal mutating func output(_ process: ProcessIdentifier,
                                into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    _ = try forward(process, current: self.process, pending: &self.output,
                    into: &output)
  }

  internal func input(_ process: ProcessIdentifier,
                      bytes: borrowing Span<UInt8>) throws(Debuggee.Error) {
    guard self.process == process, let reader else {
      throw .state
    }
    try write(reader, bytes: bytes)
  }

  private mutating func stage(_ pending: UnixDebugPending)
      throws(Debuggee.Error) {
    switch pending {
    case .output(let output):
      self.output = output
    case .ready:
      break
    case .status(let process, let status):
      guard self.process?.rawValue == UInt64(process) else {
        throw .state
      }
      DSX.log("Darwin wait status: \(status)", level: .trace, channel: .process)
      self.status = status
    }
  }

  internal mutating func enqueue(_ event: consuming Debuggee.Event,
                                 process: ProcessIdentifier, output: Bool)
      throws(Debuggee.Error) -> Debuggee.Event {
    guard output, event.completion else {
      return deliver(consume event)
    }
    try stage(sample(reader))
    guard case .some = self.output else {
      return deliver(consume event)
    }
    deferred = consume event
    return .output(process)
  }

  private mutating func deliver(_ event: consuming Debuggee.Event)
      -> Debuggee.Event {
    if case .exited = event {
      discard()
      process = nil
      attached = false
    }
    return consume event
  }

  // MARK: - Cleanup

  private mutating func discard() {
    if let reader {
      _ = DSX::close(reader)
    }
    reader = nil
    output = nil
    steps.removeAll(keepingCapacity: true)
    held.removeAll(keepingCapacity: true)
    exceptions = nil
    deferred = nil
    events.removeAll(keepingCapacity: true)
    replacement = false
    requested = false
    obsolete = false
    release = false
  }

  // MARK: - Threads

  private func plan(_ actions: borrowing Debuggee.Continuations,
                    process: ProcessIdentifier,
                    threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) -> DarwinContinuationPlan {
    var selected: ProcessThreadIdentifier?
    var signal: CInt?
    for index in 0 ..< threads.count {
      let thread = threads[index]
      let identifier = try identity(thread)
      let candidate =
          ProcessThreadIdentifier(process: process, thread: identifier)
      guard let action =
          try Debuggee.Continuation.Plan.resolve(candidate,
                                                 actions: actions) else {
        continue
      }
      if let delivered = action.signal {
        guard signal == nil || signal == delivered else {
          throw .state
        }
        signal = delivered
      }
      guard action.operation == .step else {
        continue
      }
      if selected == nil {
        selected = candidate
      }
    }
    if let selected {
      var request = kPTContinue
      _ = try step(.thread(selected), process: process, threads: threads,
                   request: &request)
      return DarwinContinuationPlan(request: request, signal: signal ?? 0,
                                    interrupt: false)
    }
    let action =
        try Debuggee.Continuation.Plan.fallback(process, actions: actions)
    return switch action?.operation {
    case .stop:
      DarwinContinuationPlan(request: kPTContinue, signal: 0, interrupt: true)
    case .resume, nil:
      DarwinContinuationPlan(request: kPTContinue,
                             signal: signal ?? action?.signal ?? 0,
                             interrupt: false)
    case .step:
      try fallback(actions, process: process, threads: threads)
    }
  }

  private func fallback(_ actions: borrowing Debuggee.Continuations,
                        process: ProcessIdentifier,
                        threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) -> DarwinContinuationPlan {
    let action =
        try Debuggee.Continuation.Plan.fallback(process, actions: actions)
    var request = kPTContinue
    _ = try step(action?.selection ?? .all, process: process, threads: threads,
                 request: &request)
    return DarwinContinuationPlan(request: request, signal: action?.signal ?? 0,
                                  interrupt: false)
  }

  private mutating func hold(_ actions: borrowing Debuggee.Continuations,
                             process: ProcessIdentifier,
                             threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    try restore(process, threads: threads)
    do throws(Debuggee.Error) {
      var selected: ThreadIdentifier?
      var count = 0
      for index in 0 ..< threads.count {
        let thread = threads[index]
        let identifier = try identity(thread)
        let candidate =
            ProcessThreadIdentifier(process: process, thread: identifier)
        let action =
            try Debuggee.Continuation.Plan.resolve(candidate, actions: actions)
        switch action?.operation {
        case nil, .stop:
          continue
        case .resume, .step:
          count += 1
          selected = count == 1 ? identifier : nil
        }
      }
      for index in 0 ..< threads.count {
        let thread = threads[index]
        let identifier = try identity(thread)
        let candidate =
            ProcessThreadIdentifier(process: process, thread: identifier)
        let action =
            try Debuggee.Continuation.Plan.resolve(candidate, actions: actions)
        if action?.operation == .resume || action?.operation == .step {
          guard selected == identifier else {
            continue
          }
          let count = try suspensions(thread)
          for _ in 0 ..< count {
            let status = thread_resume(thread)
            guard status == KERN_SUCCESS else {
              throw DarwinError.debuggee(status, invalid: .thread)
            }
            held.append(DarwinSuspension(thread: identifier, count: -1))
          }
          continue
        }
        let status = thread_suspend(thread)
        guard status == KERN_SUCCESS else {
          throw DarwinError.debuggee(status, invalid: .thread)
        }
        held.append(DarwinSuspension(thread: identifier, count: 1))
      }
    } catch {
      try restore(process, threads: threads)
      throw error
    }
  }

  private mutating func restore(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    guard !held.isEmpty else {
      return
    }
    let threads = try DarwinThreadList(process)
    try restore(process, threads: threads)
  }

  private mutating func restore(_ process: ProcessIdentifier,
                                threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    var pending = held.count
    while pending > 0 {
      pending -= 1
      let record = held[pending]
      for index in 0 ..< threads.count {
        let thread = threads[index]
        guard try identity(thread) == record.thread else {
          continue
        }
        let status = if record.count > 0 {
          thread_resume(thread)
        } else {
          thread_suspend(thread)
        }
        guard status == KERN_SUCCESS else {
          throw DarwinError.debuggee(status, invalid: .thread)
        }
        break
      }
      held.remove(at: pending)
    }
  }

}

private struct DarwinContinuationPlan {
  internal let request: CInt
  internal let signal: CInt
  internal let interrupt: Bool
}

private func awaken(_ process: pid_t) -> Bool {
  let identifier = ProcessIdentifier(rawValue: UInt64(process))
  guard let task = try? DarwinTask(identifier) else {
    return false
  }
  var resumed = false
  while true {
    var info = task_basic_info_data_t()
    let bytes = MemoryLayout<task_basic_info_data_t>.size
    let size = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(size)
    let status = withUnsafeMutablePointer(to: &info) { info in
      info.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
        task_info(task.handle, task_flavor_t(TASK_BASIC_INFO), info, &count)
      }
    }
    guard status == KERN_SUCCESS, info.suspend_count > 0 else {
      return resumed
    }
    guard task_resume(task.handle) == KERN_SUCCESS else {
      return resumed
    }
    resumed = true
  }
}

private func suspensions(_ thread: thread_t) throws(Debuggee.Error) -> Int {
  var info = thread_basic_info_data_t()
  let bytes = MemoryLayout<thread_basic_info_data_t>.size
  let size = bytes / MemoryLayout<integer_t>.size
  var count = mach_msg_type_number_t(size)
  let status = withUnsafeMutablePointer(to: &info) { info in
    info.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
      thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), info, &count)
    }
  }
  guard status == KERN_SUCCESS else {
    throw DarwinError.debuggee(status, invalid: .thread)
  }
  return Int(info.suspend_count)
}

private func translate(_ record: dsx_exception_record,
                       process: ProcessIdentifier,
                       threads: borrowing DarwinThreadList,
                       breakpoints: borrowing ActiveBreakpoints)
    throws(Debuggee.Error) -> Debuggee.Event {
  let thread = try identity(record.thread)
  let identifier = ProcessThreadIdentifier(process: process, thread: thread)
  let address = UInt64(bitPattern: record.count > 1 ? record.codes.1 : 0)
  let type = UInt64(record.type)
  let data = Debuggee.ExceptionData(count: Int(record.count)) { index in
    switch index {
    case 0: UInt64(bitPattern: record.codes.0)
    case 1: UInt64(bitPattern: record.codes.1)
    default: 0
    }
  }
  let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: address),
                             code: type, data: data, domain: .mach)
  switch record.type {
  case EXC_BREAKPOINT:
    let status = kWaitStopped | SIGTRAP << kWaitStatusShift
    let event = UnixWaitStatus.event(status, process: process, thread: thread)
    let translated =
        try DarwinDebugControl.trap(status, event: event, stepping: true,
                                    threads: threads, breakpoints: breakpoints)
    guard case .stopped(let stop) = translated else {
      throw .state
    }
    let address = stop.fault?.address ?? fault.address
    let detail = Debuggee.Fault(address: address, code: fault.code,
                                data: fault.data, domain: fault.domain)
    return .stopped(Debuggee.Stop(thread: stop.thread, reason: stop.reason,
                                  core: stop.core, fault: detail,
                                  breakpoint: stop.breakpoint,
                                  child: stop.child, snapshot: stop.snapshot,
                                  chance: stop.chance))
  case EXC_BAD_ACCESS:
    return .stopped(Debuggee.Stop(thread: identifier, reason: .exception(0x91),
                                  fault: fault))
  case EXC_SOFTWARE where record.count > 1 && record.codes.0 == EXC_SOFT_SIGNAL:
    if record.codes.1 == SIGTRAP, try process.executed {
      return .executed(identifier)
    }
    return .stopped(Debuggee.Stop(thread: identifier,
                                  reason: .signal(CInt(record.codes.1))))
  default:
    return .stopped(Debuggee.Stop(thread: identifier, reason: .exception(type),
                                  fault: fault))
  }
}

private func interrupted(_ record: borrowing dsx_exception_record) -> Bool {
  switch (record.type, record.count, record.codes.0, record.codes.1) {
  case (EXC_SOFTWARE, 2..., Int64(EXC_SOFT_SIGNAL), Int64(SIGSTOP)): true
  default: false
  }
}

private func interruption(_ record: borrowing dsx_exception_record,
                          process: ProcessIdentifier) throws(Debuggee.Error)
    -> Debuggee.Event {
  let thread = try identity(record.thread)
  let identifier = ProcessThreadIdentifier(process: process, thread: thread)
  return .stopped(Debuggee.Stop(thread: identifier, reason: .interrupt))
}

private func wait(_ process: ProcessIdentifier, reader: CInt?)
    throws(Debuggee.Error) -> UnixDebugPending {
  let pending = try sample(reader)
  guard case .ready = pending else {
    return pending
  }
  let identifier = try process.native
  var status: CInt = 0
  let result = waitpid(identifier, &status, WNOHANG)
  if result == 0 {
    return .ready
  }
  guard result == identifier else {
    throw UnixDebugProcess.failure(errno)
  }
  return .status(identifier, status)
}

private func sample(_ reader: CInt?) throws(Debuggee.Error)
    -> UnixDebugPending {
  if let reader {
    var output = Debuggee.Output()
    let count = withUnsafeMutableBytes(of: &output.bytes) { buffer in
      read(reader, buffer.baseAddress, buffer.count)
    }
    if count > 0 {
      output.count = count
      return .output(output)
    }
    if count < 0 {
      switch errno {
      case EAGAIN, EWOULDBLOCK, EINTR, EIO:
        break
      default:
        throw UnixDebugProcess.failure(errno)
      }
    }
  }
  return .ready
}

private func suspended(_ process: pid_t) -> Bool {
  var info = proc_bsdinfo()
  let count = proc_pidinfo(process, PROC_PIDTBSDINFO, 0, &info,
                           Int32(MemoryLayout<proc_bsdinfo>.size))
  return count == MemoryLayout<proc_bsdinfo>.size && info.pbi_status == SSTOP
}

#endif
