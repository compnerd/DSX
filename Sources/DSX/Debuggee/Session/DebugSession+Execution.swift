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
          switch secondary {
          case .executed where secondary.process == process,
               .exited where secondary.process == process:
            event = secondary
          default:
            debuggee.observe(secondary, global: false)
            if case .forked = secondary {
              deferred.append(secondary)
            }
          }
        }
      }
    } catch {
      error.log("stop completion failed")
      throw error
    }
    do {
      try breakpoints.complete(process, event: event, control: &control)
    } catch {
      error.log("breakpoint completion failed")
      throw error
    }
    if event.refreshable {
      do throws(Debuggee.Error) {
        try refresh(process)
      } catch .unsupported {
      } catch {
        error.log("process refresh failed")
        throw error
      }
    }
    return consume event
  }

  private mutating func classify(_ incoming: consuming Debuggee.Event)
      throws(Debuggee.Error) -> Debuggee.Event {
    if case let .stopped(stop) = incoming {
      return try .stopped(classify(stop))
    }
    complete(incoming)
    return consume incoming
  }

  @inline(never)
  private func classify(_ incoming: consuming Debuggee.Stop)
      throws(Debuggee.Error) -> Debuggee.Stop {
    let stop: Debuggee.Stop
    do {
      stop = try breakpoints.classify(consume incoming, control: control)
    } catch {
      error.log("stop classification failed")
      throw error
    }
    if let identifier = stop.breakpoint,
        let site = breakpoints.site(identifier), case .software = site.kind {
      var registers = try NativeRegisterState(stop.thread, control: control)
      try registers.set(pc: site.address.rawValue)
      try registers.commit()
    }
    return stop
  }

  internal mutating func next(global: Bool, blocking: Bool = false,
                              output: Bool = true) throws(Debuggee.Error)
      -> Debuggee.Event? {
    while true {
      let event = if deferred.isEmpty {
        try receive(global: global, blocking: blocking, output: output)
      } else {
        deferred.removeFirst()
      }
      guard case let .stopped(stop) = event, let identifier = stop.breakpoint,
          breakpoints.native(identifier) else {
        return event
      }
      if continuations.isEmpty ||
          continuations.span.action(stop.thread)?.operation == .step {
        let reason: Debuggee.StopReason =
            continuations.isEmpty ? .interrupt : .trace
        let result = stop.refined(reason: reason, fault: stop.fault,
                                  breakpoint: identifier)
        let event = Debuggee.Event.stopped(result)
        debuggee.observe(event, global: global)
        return event
      }
      let actions = continuations
      try resume(actions.span, process: stop.thread.process, recording: false)
    }
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
      case let .exited(_, status):
        if debuggee.alive {
          state = if case .terminating = previous {
            previous
          } else {
            global ? .stopped(origin) : previous
          }
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

  internal var active: Bool {
    switch state {
    case .starting, .pending, .terminating: true
    case .absent, .waiting, .stopped, .exited, .failed: false
    }
  }

  internal var phase: SessionPhase {
    guard deferred.isEmpty else {
      return .pending
    }
    return switch state {
    case .waiting: .waiting
    case .starting, .pending, .terminating: .pending
    case .absent, .stopped, .exited, .failed: .idle
    }
  }

  internal mutating func cancel() {
    if case .waiting = state {
      state = .absent
    }
  }

  internal mutating func nonstop(_ enabled: Bool, previous: Bool)
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
        continuations.removeAll(keepingCapacity: true)
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
                                process: ProcessIdentifier,
                                recording: Bool = true) throws(Debuggee.Error) {
    try debuggee.validate(actions)
    do {
      if let site = try control.checkpoint(process) {
        _ = try breakpoints.record(process, site, native: true,
                                   control: control)
        if recording {
          continuations.removeAll(keepingCapacity: true)
          for index in actions.indices {
            continuations.append(actions[index])
          }
        }
      }
      if let stop = debuggee.breakpoint(process),
          let identifier = stop.breakpoint,
          let site = breakpoints.site(identifier), site.advance {
        let thread = stop.thread
        let action = actions.action(thread)
        if let action {
          switch action.operation {
          case .resume, .step:
            guard try advance(stop, site: site,
                              operation: action.operation) else {
              return
            }
          case .stop:
            break
          }
        }
      }
      try breakpoints.prepare(process, control: &control)
      try resume(actions)
    } catch let operation {
      operation.log("failed to resume debuggee")
      do {
        try breakpoints.recover(process, control: &control)
        try control.recover()
      } catch {
        error.log("failed to recover debuggee after resume")
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
                                site: borrowing BreakpointSite,
                                operation: Debuggee.Continuation.Operation)
      throws(Debuggee.Error) -> Bool {
    if case .software = site.kind {
      // Register writes and restored snapshots can move the PC away from the
      // trap. Reinstall it without stepping unrelated code.
      let registers = try NativeRegisterState(stop.thread, control: control)
      let address = try Debuggee.Address(rawValue: registers.pc)
      guard ABI.breakpoint(address).address == site.address else {
        return true
      }
    }
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
      if operation == .step, case let .stopped(result) = event,
          result.thread == stop.thread, let identifier = result.breakpoint,
          let site = breakpoints.site(identifier), case .software = site.kind {
        try breakpoints.prepare(stop.thread.process, control: &control)
        let trace =
            result.refined(reason: .trace, fault: result.fault, breakpoint: nil)
        let event = Debuggee.Event.stopped(trace)
        debuggee.observe(event, global: true)
        deferred.append(event)
        return false
      }
      guard case let .stopped(result) = event, result.thread == stop.thread,
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
