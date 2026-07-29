// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

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
