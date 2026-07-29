// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum SessionPhase: Sendable {
  case idle
  case pending
  case waiting
}

internal enum SessionClosure: Sendable {
  case normal
  case failure
}

internal struct DebugSession: ~Copyable, Sendable {
  internal enum Origin: Sendable {
    case attached
    case launched
  }

  internal enum State: Sendable {
    case absent
    case waiting(PendingAttach)
    case starting(Origin)
    case pending(Origin)
    case stopped(Origin)
    case exited(Origin, Debuggee.Exit)
    case failed(Origin?)

    fileprivate var origin: Origin? {
      switch self {
      case .starting(let origin), .pending(let origin), .stopped(let origin),
          .exited(let origin, _):
        origin
      case .failed(let origin):
        origin
      case .absent, .waiting:
        nil
      }
    }
  }

  internal typealias PendingAttach =
      (name: String, excluded: Array<ProcessIdentifier>)

  internal var breakpoints = BreakpointTable()
  internal var files = FileSystem()
  internal var allocations = Array<MemoryAllocation>()
  internal var control = NativeDebugControl()
  internal var launch: Debuggee.Launch
  internal var debuggee: Debuggee
  internal var snapshots = Array<SavedRegisters>()
  internal var sequence: UInt32 = 0
  internal var signals = SignalSet()
  private var deferred = Array<Debuggee.Event>()
  private var error: Debuggee.Error?
  internal var state = State.absent

  internal init(launch: consuming Debuggee.Launch = Debuggee.Launch(),
                debuggee: consuming Debuggee = Debuggee()) {
    self.launch = consume launch
    self.debuggee = consume debuggee
    error = nil
  }

  internal var attached: Bool {
    if case .some(.attached) = origin {
      true
    } else {
      false
    }
  }

  internal var failed: Bool {
    if case .failed = state {
      true
    } else {
      false
    }
  }
}

// MARK: - Lifecycle

extension DebugSession {
  internal init(_ initial: consuming DSX.Debuggee?) throws(Debuggee.Error) {
    self.init()
    guard let initial else {
      return
    }
    switch initial {
    case .attach(let value):
      try attach(resolve(value))
    case .launch(let executable, let arguments):
      launch.executable = executable
      launch.arguments = consume arguments
      _ = try spawn()
    }
    try settle()
  }

  internal mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    switch state {
    case .absent, .waiting, .failed(nil):
      break
    case .starting, .pending, .stopped, .exited, .failed(.some(_)):
      throw .state
    }
    error = nil
    state = .starting(.attached)
    do throws(Debuggee.Error) {
      try control.attach(process)
    } catch {
      state = .failed(nil)
      throw error
    }
    debuggee.insert(Debuggee.Process(identifier: process))
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let previous = state
    guard case .some = origin else {
      throw .state
    }
    do throws(Debuggee.Error) {
      try deallocate(process)
      if case .some = debuggee.parent(process) {
        breakpoints.forget(process)
      } else {
        try breakpoints.clear(process, context: &control)
      }
      try control.detach(process, stopped: stopped)
    } catch {
      state = previous
      throw error
    }
    debuggee.remove(process)
    snapshots.removeAll { snapshot in
      snapshot.thread.process == process
    }
    state = debuggee.processes.isEmpty ? .absent : previous
  }

  internal mutating func ignore(_ fork: borrowing Debuggee.Fork)
      throws(Debuggee.Error) {
    try breakpoints.clear(fork.child.process, context: &control)
    try control.discard(fork)
    debuggee.remove(fork.child.process)
    let action = Debuggee.Continuation(selection: .process(fork.parent.process),
                                       operation: .resume)
    let actions: InlineArray<1, Debuggee.Continuation> = [action]
    try resume(actions.span, process: fork.parent.process)
  }

  internal mutating func ignore(_ thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    let action = Debuggee.Continuation(selection: .process(thread.process),
                                       operation: .resume)
    let actions: InlineArray<1, Debuggee.Continuation> = [action]
    try resume(actions.span, process: thread.process)
  }

  internal mutating func discard(_ event: borrowing Debuggee.Event)
      throws(Debuggee.Error) {
    try control.discard(event)
  }

  internal mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    guard let origin else {
      throw .state
    }
    let previous = state
    do throws(Debuggee.Error) {
      try control.terminate(process)
    } catch {
      state = previous
      throw error
    }
    state = .pending(origin)
  }

  internal mutating func input(_ process: ProcessIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    try control.input(process, bytes: bytes)
  }

  internal mutating func output(_ process: ProcessIdentifier,
                                into bytes: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    try control.output(process, into: &bytes)
  }

  internal mutating func ignore(_ exceptions: Debuggee.ExceptionMask)
      throws(Debuggee.Error) {
    try control.ignore(exceptions)
  }

  internal mutating func spawn() throws(Debuggee.Error) -> ProcessIdentifier {
    switch state {
    case .absent, .failed(nil):
      break
    case .starting, .pending, .stopped, .exited, .failed(.some(_)), .waiting:
      throw .process
    }
    guard debuggee.processes.isEmpty, case .some = launch.executable else {
      throw .process
    }
    error = nil
    DSX.log("launching debuggee", level: .trace, channel: .process)
    state = .starting(.launched)
    let process: ProcessIdentifier
    do throws(Debuggee.Error) {
      process = try control.launch(launch)
    } catch {
      state = .failed(nil)
      throw error
    }
    DSX.log("debuggee \(process.rawValue) launched", level: .trace,
            channel: .process)
    debuggee.insert(Debuggee.Process(identifier: process))
    return process
  }

  internal mutating func rollback() {
    if case .exited = state {
      debuggee = Debuggee()
      state = .failed(nil)
      return
    }
    guard let origin, let process = debuggee.processes.first?.identifier else {
      state = .failed(nil)
      return
    }
    var released = false
    do throws(Debuggee.Error) {
      switch (origin, launch.detach) {
      case (.attached, _), (.launched, true):
        try control.detach(process, stopped: false)
      case (.launched, false):
        state = .pending(origin)
        try control.terminate(process)
        _ = try drain(output: false)
      }
      released = true
    } catch {
      DSX.log("failed to release debuggee after launch error: \(error)",
              level: .warning, channel: .process)
    }
    if released {
      debuggee = Debuggee()
    }
    state = .failed(released ? nil : origin)
  }

  @discardableResult
  internal mutating func settle() throws(Debuggee.Error) -> Debuggee.Event? {
    do throws(Debuggee.Error) {
      let event = try drain(output: true)
      if let error = failure() {
        throw error
      }
      return event
    } catch {
      rollback()
      throw error
    }
  }

  @discardableResult
  private mutating func drain(output: Bool) throws(Debuggee.Error)
      -> Debuggee.Event? {
    var result: Debuggee.Event?
    while active {
      if let event = try next(global: true, blocking: true, output: output),
          event.completion {
        result = event
      }
    }
    return result
  }

  private mutating func resolve(_ value: String) throws(Debuggee.Error)
      -> ProcessIdentifier {
    if let identifier = decimal(value.utf8Span.span) {
      return ProcessIdentifier(rawValue: identifier)
    }
    guard let process = try process(value) else {
      throw .process
    }
    return process
  }
}

// MARK: - Events

extension DebugSession {
  private mutating func prepare(_ incoming: consuming Debuggee.Event,
                                global: Bool) throws(Debuggee.Error)
      -> Debuggee.Event {
    var event = try classify(consume incoming)
    guard event.completion else {
      return consume event
    }
    let process = event.process
    do {
      if global {
        try control.complete(event)
        while let incoming = control.collect() {
          let secondary = try classify(incoming)
          if case .exited = secondary {
            event = secondary
          } else {
            debuggee.observe(secondary, global: false)
          }
        }
      }
    } catch {
      DSX.log("stop completion failed: \(error)", level: .error,
              channel: .process)
      throw error
    }
    if case .forked(let fork) = event {
      breakpoints.inherit(fork)
    }
    do {
      try breakpoints.complete(process, event: event, context: &control)
    } catch {
      DSX.log("breakpoint completion failed: \(error)", level: .error,
              channel: .process)
      throw error
    }
    if event.refreshable {
      do throws(Debuggee.Error) {
        try refresh(process)
      } catch .unsupported {
      } catch {
        DSX.log("process refresh failed: \(error)", level: .error,
                channel: .process)
        throw error
      }
    }
    return consume event
  }

  private mutating func classify(_ incoming: consuming Debuggee.Event)
      throws(Debuggee.Error) -> Debuggee.Event {
    let event: Debuggee.Event
    do {
      event = try breakpoints.classify(consume incoming, context: &control)
    } catch {
      DSX.log("stop classification failed: \(error)", level: .error,
              channel: .process)
      throw error
    }
    if case .stopped(let stop) = event, let identifier = stop.breakpoint,
        let site = breakpoints.site(identifier), case .software = site.kind {
      try program(stop.thread, value: site.address.rawValue)
    }
    complete(event)
    return event
  }

  internal mutating func next(global: Bool, blocking: Bool = false,
                              output: Bool = true)
      throws(Debuggee.Error) -> Debuggee.Event? {
    guard deferred.isEmpty else {
      return deferred.removeFirst()
    }
    return try receive(global: global, blocking: blocking, output: output)
  }

  private mutating func receive(global: Bool, blocking: Bool,
                                output: Bool = true) throws(Debuggee.Error)
      -> Debuggee.Event? {
    guard active else {
      return nil
    }
    guard let incoming =
        try control.event(blocking: blocking, output: output,
                          signals: signals) else {
      return nil
    }
    DSX.log("received debuggee event for \(incoming.process.rawValue)",
            level: .trace, channel: .process)
    let previous = state
    let event: Debuggee.Event
    do throws(Debuggee.Error) {
      event = try prepare(incoming, global: global)
    } catch {
      state = .failed(origin)
      self.error = error
      throw error
    }
    debuggee.observe(event, global: global)
    let completion = global ? event.completion : event.exited
    if completion, let origin = previous.origin {
      switch event {
      case .exited(_, let status):
        if debuggee.alive {
          state = global ? .stopped(origin) : previous
        } else {
          state = .exited(origin, status)
          if case .starting = previous {
            error = .premature(status.code)
          }
        }
      case .executed, .forked, .stopped:
        state = .stopped(origin)
      case .image, .output, .started, .terminated:
        break
      }
    }
    return event
  }

  internal mutating func failure() -> Debuggee.Error? {
    error.take()
  }

  internal var active: Bool {
    switch state {
    case .starting, .pending:
      true
    case .absent, .waiting, .stopped, .exited, .failed:
      false
    }
  }

  internal var phase: SessionPhase {
    guard deferred.isEmpty else {
      return .pending
    }
    return switch state {
    case .waiting: .waiting
    case .starting, .pending: .pending
    case .absent, .stopped, .exited, .failed: .idle
    }
  }

  internal mutating func cancel() {
    if case .waiting = state {
      state = .absent
    }
  }

  internal mutating func mode(_ enabled: Bool, previous: Bool)
      throws(Debuggee.Error) {
    if enabled {
      return
    }
    guard previous, active,
        let process = debuggee.processes.first?.identifier else {
      return
    }
    try control.interrupt(process)
    try drain(output: true)
  }

  internal mutating func libraries(_ enabled: Bool) {
    control.libraries(enabled)
  }

  internal mutating func syscalls(_ calls: consuming Array<UInt64>?)
      throws(Debuggee.Error) {
    try control.syscalls(consume calls)
  }

  internal func watchpoints(_ process: ProcessIdentifier?)
      throws(Debuggee.Error) -> Int? {
    if let process {
      try control.watchpoints(process)
    } else {
      try HardwareBreakpoint.capacity
    }
  }
}

// MARK: - Execution

extension DebugSession {
  internal mutating func interrupt(_ process: ProcessIdentifier)
      throws(Debuggee.Error) -> Bool {
    guard active else {
      return false
    }
    while let event = try receive(global: true, blocking: false,
                                  output: false) {
      let completion = event.completion
      deferred.append(event)
      if completion {
        return false
      }
    }
    try control.interrupt(process)
    if let origin {
      state = .pending(origin)
    }
    return true
  }

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations,
                                process: ProcessIdentifier)
      throws(Debuggee.Error) {
    try debuggee.prepare(actions)
    do {
      if let stop = debuggee.breakpoint(process),
          let identifier = stop.breakpoint, breakpoints.advance(identifier) {
        let thread = stop.thread
        let action =
            try Debuggee.Continuation.Plan.resolve(thread, actions: actions)
        if let action {
          switch action.operation {
          case .resume, .step:
            guard try advance(stop, operation: action.operation) else {
              return
            }
          case .stop:
            break
          }
        }
      }
      try breakpoints.prepare(process, context: &control)
      try resume(actions)
    } catch let operation {
      DSX.log("failed to resume debuggee: \(operation)", level: .error,
              channel: .process)
      do {
        try breakpoints.recover(process, context: &control)
        try control.recover()
      } catch {
        DSX.log("failed to recover debuggee after resume: \(error)",
                level: .error, channel: .process)
      }
      throw operation
    }
  }

  private mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let origin else {
      throw .state
    }
    try control.resume(actions)
    debuggee.resume(actions)
    state = .pending(origin)
  }

  private mutating func advance(_ stop: borrowing Debuggee.Stop,
                                operation: Debuggee.Continuation.Operation)
      throws(Debuggee.Error) -> Bool {
    DSX.log("stepping over breakpoint", level: .trace, channel: .process)
    let step =
        Debuggee.Continuation(selection: .thread(stop.thread), operation: .step)
    let actions: InlineArray<1, Debuggee.Continuation> = [step]
    try resume(actions.span)
    var output = true
    while active {
      guard let event =
          try receive(global: true, blocking: true, output: output) else {
        continue
      }
      guard event.completion else {
        deferred.append(event)
        if case .output = event {
          output = false
        }
        continue
      }
      if operation == .step, case .stopped(let result) = event,
          result.thread == stop.thread, let identifier = result.breakpoint,
          let site = breakpoints.site(identifier), case .software = site.kind {
        try breakpoints.prepare(stop.thread.process, context: &control)
        let trace =
            Debuggee.Stop(thread: result.thread, reason: .trace,
                          core: result.core, fault: result.fault,
                          child: result.child, snapshot: result.snapshot,
                          chance: result.chance)
        let event = Debuggee.Event.stopped(trace)
        debuggee.observe(event, global: true)
        deferred.append(event)
        return false
      }
      guard case .stopped(let result) = event, result.thread == stop.thread,
          result.reason == .trace else {
        deferred.append(event)
        return false
      }
      switch operation {
      case .resume:
        return true
      case .step:
        deferred.append(event)
        return false
      case .stop:
        return false
      }
    }
    throw .state
  }
}

// MARK: - Attachment

extension DebugSession {
  internal mutating func poll() throws(Debuggee.Error) {
    guard case .waiting(let attachment) = state else {
      return
    }
    let excluded = attachment.excluded
    let process = try process(attachment.name) { process in
      excluded.contains(process) == false
    }
    guard let process else {
      return
    }
    try attach(process)
  }

  internal mutating func queue(_ name: String, existing: Bool)
      throws(Debuggee.Error) {
    switch state {
    case .absent, .failed(nil):
      break
    case .starting, .pending, .stopped, .exited, .failed(.some(_)), .waiting:
      throw .state
    }
    var excluded = Array<ProcessIdentifier>()
    if existing {
      _ = try process(name) { process in
        excluded.append(process)
        return false
      }
    }
    state = .waiting((name: name, excluded: excluded))
  }
}

// MARK: - Cleanup

extension DebugSession {
  internal mutating func close(cause: SessionClosure) throws(Debuggee.Error) {
    var failure: Debuggee.Error?
    var held = false
    while let allocation = allocations.popLast() {
      do throws(Debuggee.Error) {
        try NativeMemory.deallocate(allocation.process,
                                    address: allocation.address,
                                    size: allocation.size, control: &control)
      } catch {
        if case .none = failure {
          failure = error
        }
      }
    }
    do throws(Debuggee.Error) {
      try files.clear()
    } catch {
      if case .none = failure {
        failure = error
      }
    }
    for process in debuggee.processes {
      do throws(Debuggee.Error) {
        try breakpoints.clear(process.identifier, context: &control)
      } catch {
        if case .none = failure {
          failure = error
        }
      }
    }
    deferred.removeAll(keepingCapacity: true)
    do throws(Debuggee.Error) {
      try release(cause)
    } catch {
      held = true
      if case .none = failure {
        failure = error
      }
    }
    snapshots.removeAll(keepingCapacity: true)
    if held {
      state = .failed(origin)
    } else {
      debuggee = Debuggee()
      state = .absent
    }
    if let failure {
      throw failure
    }
  }

  private mutating func release(_ cause: SessionClosure)
      throws(Debuggee.Error) {
    guard !debuggee.processes.isEmpty else {
      return try control.close()
    }
    guard let origin else {
      return try control.close()
    }
    switch (origin, cause, launch.detach) {
    case (.attached, _, _), (.launched, .failure, true):
      try control.close()
    case (.launched, _, _):
      var pending = false
      for process in debuggee.processes {
        if case .exited = process.state {
          continue
        }
        try control.terminate(process.identifier)
        pending = true
      }
      guard pending else {
        return try control.close()
      }
      while debuggee.alive {
        state = .pending(origin)
        _ = try next(global: true, blocking: true, output: false)
      }
    }
  }
}

extension DebugSession {
  private var origin: Origin? {
    state.origin
  }
}
