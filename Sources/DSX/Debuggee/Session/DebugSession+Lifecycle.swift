// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

// MARK: - Lifecycle

extension DebugSession {
  internal init(_ initial: consuming DSX.Debuggee?,
                events: borrowing NativeEventSource = NativeEventSource())
      throws(Debuggee.Error) {
    self.init()
    events.configure(&control)
    guard let initial else {
      return
    }
    switch initial {
    case let .attach(value):
      try attach(ProcessIdentifier(resolving: value))
    case let .launch(executable, arguments):
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
    case .starting, .pending, .terminating, .stopped, .exited,
         .failed(.some(_)):
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

  @inline(never)
  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    guard case .some = origin else {
      throw .state
    }
    switch debuggee.state(process) {
    case .exited:
      // Exit reporting retains the record, but native resources are gone.
      break
    default:
      try deallocate(process)
      // RSP leaves breakpoint cleanup on detach unspecified. Clients manage
      // their sites with Z/z; retain that state and remove only DSX's traps.
      // Disconnect cleanup remains separate and restores all sites.
      try breakpoints.clear(process, preserving: true, control: &control)
      try control.detach(process, stopped: stopped)
    }
    debuggee.remove(process)
    snapshots.discard(process)
    if debuggee.processes.isEmpty {
      state = .absent
    }
  }

  internal mutating func ignore(_ fork: borrowing Debuggee.Fork,
                                resume resuming: Bool = true)
      throws(Debuggee.Error) {
    try breakpoints.clear(fork.child.process, control: &control)
    try control.discard(fork)
    debuggee.remove(fork.child.process)
    guard resuming else {
      return
    }
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

  internal mutating func terminate() throws(Debuggee.Error) {
    var failure: Debuggee.Error?
    for index in debuggee.processes.indices {
      if case .exited = debuggee.processes[index].state {
        continue
      }
      do throws(Debuggee.Error) {
        try terminate(debuggee.processes[index].identifier)
      } catch {
        if failure == nil {
          failure = error
        }
      }
    }
    if let failure {
      throw failure
    }
    if let origin {
      state = .terminating(origin)
    }
  }

  @inline(never)
  internal mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    guard let origin else {
      throw .state
    }
    try control.terminate(process)
    state = .pending(origin)
  }

  internal mutating func spawn() throws(Debuggee.Error) -> ProcessIdentifier {
    switch state {
    case .absent, .failed(nil):
      break
    case .starting, .pending, .terminating, .stopped, .exited,
        .failed(.some(_)), .waiting:
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
      error.log("failed to release debuggee after launch error",
                level: .warning)
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
      if let error = error.take() {
        throw error
      }
      return event
    } catch {
      rollback()
      throw error
    }
  }

  @discardableResult
  internal mutating func drain(output: Bool) throws(Debuggee.Error)
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
}

// MARK: - Attachment

extension DebugSession {
  internal mutating func poll() throws(Debuggee.Error) {
    guard case let .waiting(attachment) = state else {
      return
    }
    var lookup = try ProcessLookup(attachment.name)
    let process = try lookup.first(excluding: attachment.excluded)
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
    case .starting, .pending, .terminating, .stopped, .exited,
        .failed(.some(_)), .waiting:
      throw .state
    }
    var excluded = Array<ProcessIdentifier>()
    if existing {
      var lookup = try ProcessLookup(name)
      while let process = try lookup.next() {
        excluded.append(process)
      }
    }
    state = .waiting((name: name, excluded: excluded))
  }
}

// MARK: - Cleanup

extension DebugSession {
  internal mutating func close(cause: SessionClosure) throws(Debuggee.Error) {
    var failure = deallocate()
    var held = false
    do throws(Debuggee.Error) {
      try files.clear()
    } catch {
      if case .none = failure {
        failure = error
      }
    }
    for process in debuggee.processes {
      do throws(Debuggee.Error) {
        try breakpoints.clear(process.identifier, control: &control)
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
    snapshots.clear()
    if held {
      state = .failed(origin)
    } else {
      allocations.removeAll(keepingCapacity: true)
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
  internal mutating func complete(_ event: borrowing Debuggee.Event) {
    let process: ProcessIdentifier
    switch event {
    case let .executed(thread):
      process = thread.process
    case let .exited(identifier, _):
      process = identifier
    case let .terminated(thread, _):
      return snapshots.discard(thread.process, thread: thread.thread)
    case let .forked(fork):
      return breakpoints.inherit(fork)
    case .image, .output, .started, .stopped:
      return
    }
    allocations.removeAll { allocation in
      allocation.process == process
    }
    snapshots.discard(process)
    breakpoints.forget(process)
  }
}
