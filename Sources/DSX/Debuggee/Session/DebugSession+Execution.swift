// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

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
