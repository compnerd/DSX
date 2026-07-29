// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal struct Process: Sendable {
    internal enum State: Sendable {
      case launching
      case running
      case stopped
      case exited(Exit)
    }

    internal struct Info: Sendable {
      internal let process: ProcessIdentifier
      internal let parent: ProcessIdentifier?
      internal let name: String
      internal let arguments: Array<String>
      internal let architecture: String
      internal let system: String?
      internal let cpu: UInt64?
      internal let subtype: UInt64?

      internal init(process: ProcessIdentifier, parent: ProcessIdentifier?,
                    name: consuming String,
                    arguments: consuming Array<String> = [],
                    architecture: consuming String,
                    system: consuming String? = nil, cpu: UInt64? = nil,
                    subtype: UInt64? = nil) {
        self.process = process
        self.parent = parent
        self.name = consume name
        self.arguments = consume arguments
        self.architecture = consume architecture
        self.system = consume system
        self.cpu = cpu
        self.subtype = subtype
      }
    }

    internal let identifier: ProcessIdentifier
    internal var parent: ProcessIdentifier?
    internal var info: Info?
    internal var state: State
    internal var threads: Array<Thread>
    internal var current: ThreadIdentifier?

    internal init(identifier: ProcessIdentifier,
                  parent: ProcessIdentifier? = nil, info: consuming Info? = nil,
                  state: State = .launching,
                  threads: consuming Array<Thread> = [],
                  current: ThreadIdentifier? = nil) {
      self.identifier = identifier
      self.parent = parent
      self.info = consume info
      self.state = state
      self.threads = consume threads
      self.current = current
    }
  }
}

// MARK: - Threads

extension Debuggee.Process {
  internal borrowing func contains(_ identifier: ProcessThreadIdentifier)
      -> Bool {
    index(identifier) != nil
  }

  internal borrowing func state(_ identifier: ProcessThreadIdentifier)
      -> Debuggee.Thread.State? {
    guard let index = index(identifier) else {
      return nil
    }
    return threads[index].state
  }

  internal borrowing func alive(_ identifier: ProcessThreadIdentifier) -> Bool {
    guard let state = state(identifier) else {
      return false
    }
    return switch state {
    case .running, .stepping, .stopped: true
    case .terminated: false
    }
  }

  internal borrowing func breakpoint() -> Debuggee.Stop? {
    for thread in threads {
      guard case .stopped(let stop) = thread.state,
          case .some = stop.breakpoint else {
        continue
      }
      return stop
    }
    return nil
  }

  internal borrowing func selected() -> ProcessThreadIdentifier? {
    if let current {
      let identifier =
          ProcessThreadIdentifier(process: self.identifier, thread: current)
      if alive(identifier) {
        return identifier
      }
    }
    for thread in threads where alive(thread.identifier) {
      return thread.identifier
    }
    return nil
  }

  internal mutating func insert(_ identifier: ProcessThreadIdentifier) {
    if case .some = index(identifier) {
      return
    }
    threads.append(Debuggee.Thread(identifier: identifier, state: .running))
    current = identifier.thread
    state = .running
  }

  internal mutating func refresh(_ identifiers: borrowing Debuggee.Thread.IDs) {
    var stored = threads.count
    while stored > 0 {
      stored -= 1
      let identifier = threads[stored].identifier
      var found = false
      for index in 0 ..< identifiers.count
          where identifiers[index] == identifier {
        found = true
        break
      }
      if found {
        continue
      }
      threads.remove(at: stored)
    }
    for index in 0 ..< identifiers.count {
      insert(identifiers[index])
    }
  }

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations) {
    var applied = false
    for index in threads.indices {
      let identifier = threads[index].identifier
      guard let action =
          Debuggee.Continuation.Plan.select(identifier, actions: actions) else {
        continue
      }
      threads[index].state = switch action.operation {
      case .resume: .running
      case .step: .stepping
      case .stop: threads[index].state
      }
      switch action.operation {
      case .resume, .step:
        applied = true
      case .stop:
        break
      }
    }
    if applied {
      state = .running
    }
  }

  internal mutating func execute(_ identifier: ProcessThreadIdentifier) {
    let stop = Debuggee.Stop(thread: identifier, reason: .executed)
    threads.removeAll(keepingCapacity: true)
    threads.append(Debuggee.Thread(identifier: identifier,
                                   state: .stopped(stop)))
    current = identifier.thread
    state = .stopped
    info = nil
  }

  internal mutating func observe(_ stop: Debuggee.Stop, global: Bool) {
    if global {
      for index in threads.indices {
        let thread = threads[index]
        switch thread.state {
        case .running, .stepping:
          let stopped =
              Debuggee.Stop(thread: thread.identifier, reason: .signal(0))
          threads[index].state = .stopped(stopped)
        case .stopped, .terminated:
          break
        }
      }
    }
    if let index = index(stop.thread) {
      threads[index].state = .stopped(stop)
    } else {
      threads.append(Debuggee.Thread(identifier: stop.thread,
                                     state: .stopped(stop)))
    }
    current = stop.thread.thread
    state = .stopped
  }

  internal mutating func terminate(_ identifier: ProcessThreadIdentifier) {
    guard let index = index(identifier) else {
      return
    }
    threads.remove(at: index)
    if current == identifier.thread {
      current = threads.first?.identifier.thread
    }
  }

  internal mutating func exit(_ status: Debuggee.Exit) {
    state = .exited(status)
    for index in threads.indices {
      threads[index].state = .terminated
    }
  }

  private borrowing func index(_ identifier: ProcessThreadIdentifier) -> Int? {
    threads.firstIndex { thread in
      thread.identifier == identifier
    }
  }
}
