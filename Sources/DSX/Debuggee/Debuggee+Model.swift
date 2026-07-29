// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

// MARK: - Lookup

extension Debuggee {
  internal var alive: Bool {
    for process in processes {
      if case .exited = process.state {
        continue
      }
      return true
    }
    return false
  }

  internal borrowing func contains(_ identifier: ProcessIdentifier) -> Bool {
    index(identifier) != nil
  }

  internal borrowing func contains(_ identifier: ProcessThreadIdentifier)
      -> Bool {
    guard let index = index(identifier.process) else {
      return false
    }
    return processes[index].contains(identifier)
  }

  internal borrowing func state(_ identifier: ProcessIdentifier)
      -> Debuggee.Process.State? {
    guard let index = index(identifier) else {
      return nil
    }
    return processes[index].state
  }

  internal borrowing func state(_ identifier: ProcessThreadIdentifier)
      -> Debuggee.Thread.State? {
    guard let index = index(identifier.process) else {
      return nil
    }
    return processes[index].state(identifier)
  }

  internal borrowing func parent(_ identifier: ProcessIdentifier)
      -> ProcessIdentifier? {
    guard let index = index(identifier) else {
      return nil
    }
    return processes[index].parent
  }

  internal borrowing func breakpoint(_ identifier: ProcessIdentifier)
      -> Debuggee.Stop? {
    guard let index = index(identifier) else {
      return nil
    }
    return processes[index].breakpoint()
  }

  internal borrowing func name(_ identifier: ProcessIdentifier) -> String? {
    guard let index = index(identifier) else {
      return nil
    }
    return processes[index].info?.name
  }

  internal borrowing func process(_ selection: Debuggee.Thread.Selection)
      -> ProcessIdentifier? {
    switch selection {
    case .all, .any:
      processes.first?.identifier
    case .process(let process):
      process
    case .thread(let thread):
      thread.process
    }
  }

  internal borrowing func resolve(_ selection: Debuggee.Thread.Selection)
      -> ProcessThreadIdentifier? {
    switch selection {
    case .all:
      nil
    case .any:
      selected()
    case .process(let process):
      selected(process)
    case .thread(let thread):
      contains(thread) ? thread : nil
    }
  }

  internal borrowing func resolve(_ identifier: ThreadIdentifier)
      -> ProcessThreadIdentifier? {
    var match: ProcessThreadIdentifier?
    for process in processes {
      let candidate = ProcessThreadIdentifier(process: process.identifier,
                                              thread: identifier)
      if process.alive(candidate) {
        if case .some = match {
          return nil
        }
        match = candidate
      }
    }
    return match
  }

  internal borrowing func alive(_ identifier: ProcessThreadIdentifier) -> Bool {
    guard let index = index(identifier.process) else {
      return false
    }
    return processes[index].alive(identifier)
  }
}

// MARK: - Storage

extension Debuggee {
  internal mutating func insert(_ process: consuming Debuggee.Process) {
    let identifier = process.identifier
    if let index = index(identifier) {
      processes[index] = consume process
    } else {
      processes.append(consume process)
    }
  }

  internal mutating func remove(_ process: ProcessIdentifier) {
    processes.removeAll { candidate in
      candidate.identifier == process
    }
  }

  internal mutating func refresh(_ process: ProcessIdentifier,
                                 threads: borrowing Debuggee.Thread.IDs) {
    guard let index = index(process) else {
      return
    }
    processes[index].refresh(threads)
  }

  internal mutating func update(_ info: consuming Debuggee.Process.Info) {
    let identifier = info.process
    ensure(identifier)
    guard let index = index(identifier) else {
      return
    }
    processes[index].parent = info.parent
    processes[index].info = consume info
  }
}

// MARK: - Execution

extension Debuggee {
  internal borrowing func prepare(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    for index in 0 ..< actions.count {
      guard contains(actions[index].selection) else {
        throw .thread
      }
    }
    for process in processes {
      for thread in process.threads {
        let identifier = thread.identifier
        _ = try Debuggee.Continuation.Plan.resolve(identifier, actions: actions)
      }
    }
  }

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations) {
    for index in processes.indices {
      processes[index].resume(actions)
    }
  }
}

// MARK: - Events

extension Debuggee {
  internal mutating func observe(_ event: borrowing Debuggee.Event,
                                 global: Bool = true) {
    switch event {
    case .executed(let thread):
      ensure(thread.process)
      if let index = index(thread.process) {
        processes[index].execute(thread)
      }
    case .exited(let process, let status):
      if let index = index(process) {
        processes[index].exit(status)
      }
    case .forked(let fork):
      let parent = Debuggee.Stop(thread: fork.parent,
                                 reason: fork.vfork ? .vfork : .fork,
                                 child: fork.child)
      if let index = index(fork.parent.process) {
        processes[index].observe(parent, global: false)
      }
      let stop =
          Debuggee.Stop(thread: fork.child, reason: fork.vfork ? .vfork : .fork)
      insert(Debuggee.Process(identifier: fork.child.process,
                              parent: fork.parent.process, state: .stopped,
                              threads: [
                               Debuggee.Thread(identifier: fork.child,
                                               state: .stopped(stop)),
                             ], current: fork.child.thread))
    case .image, .output:
      break
    case .started(let thread):
      insert(thread)
    case .stopped(let stop):
      update(stop, global: global)
    case .terminated(let thread, _):
      if let index = index(thread.process) {
        processes[index].terminate(thread)
      }
    }
  }
}

// MARK: - Internals

extension Debuggee {
  private borrowing func selected() -> ProcessThreadIdentifier? {
    for process in processes {
      if let thread = process.selected() {
        return thread
      }
    }
    return nil
  }

  private borrowing func selected(_ identifier: ProcessIdentifier)
      -> ProcessThreadIdentifier? {
    for process in processes where process.identifier == identifier {
      return process.selected()
    }
    return nil
  }

  private borrowing func contains(_ selection: Debuggee.Thread.Selection)
      -> Bool {
    switch selection {
    case .all, .any:
      return processes.contains { process in
        process.threads.count > 0
      }
    case .process(let process):
      guard let index = index(process) else {
        return false
      }
      return processes[index].threads.isEmpty == false
    case .thread(let thread):
      return contains(thread)
    }
  }

  internal mutating func insert(_ thread: ProcessThreadIdentifier) {
    ensure(thread.process)
    if let index = index(thread.process) {
      processes[index].insert(thread)
    }
  }

  private mutating func update(_ stop: Debuggee.Stop, global: Bool = true) {
    ensure(stop.thread.process)
    if let index = index(stop.thread.process) {
      processes[index].observe(stop, global: global)
    }
  }

  private mutating func ensure(_ identifier: ProcessIdentifier) {
    if contains(identifier) {
      return
    }
    insert(Debuggee.Process(identifier: identifier, state: .stopped))
  }

  private borrowing func index(_ identifier: ProcessIdentifier) -> Int? {
    for index in processes.indices
        where processes[index].identifier == identifier {
      return index
    }
    return nil
  }
}
