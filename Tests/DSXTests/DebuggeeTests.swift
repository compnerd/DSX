// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct DebuggeeTests {
  @Test
  internal func lifecycle() {
    let process = ProcessIdentifier(rawValue: 9)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 4))
    var debuggee = Debuggee()
    debuggee.observe(.started(thread))
    if case .running = debuggee.state(process) {
    } else {
      Issue.record("started process is not running")
    }
    #expect(Debuggee.Event.started(thread).completion == false)
    #expect(Debuggee.Event.terminated(thread, 0).completion == false)
    debuggee.observe(.terminated(thread, 0))
    #expect(debuggee.contains(thread) == false)
    debuggee.observe(.started(thread))
    debuggee.observe(.exited(process, .exited(0)))
    if case .exited(.exited(0)) = debuggee.state(process) {
    } else {
      Issue.record("process did not record its exit status")
    }
    #expect(debuggee.alive == false)
  }

  @Test
  internal func execution() {
    let process = ProcessIdentifier(rawValue: 9)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 4))
    let stale =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 5))
    let info = Debuggee.Process.Info(process: process, parent: nil,
                                     name: "inferior", architecture: "arm64")
    var debuggee =
        Debuggee(processes: [
          Debuggee.Process(identifier: process, info: info, state: .running,
                           threads: [Debuggee.Thread(identifier: stale)]),
        ])
    debuggee.observe(.executed(thread))
    #expect(debuggee.contains(thread))
    #expect(debuggee.contains(stale) == false)
    #expect(debuggee.name(process) == nil)
    guard case .stopped(let stop) = debuggee.state(thread),
        stop.reason == .executed else {
      Issue.record("execution did not establish a fresh stopped thread")
      return
    }
  }

  @Test
  internal func retry() throws {
    var session = DebugSession()
    session.state = .failed(nil)
    try session.queue("inferior", existing: false)
    #expect(session.phase == .waiting)
    session.cancel()
    #expect(session.phase == .idle)
  }

  @Test
  internal func closure() throws {
    let process = ProcessIdentifier(rawValue: 9)
    let debuggee =
        Debuggee(processes: [
          Debuggee.Process(identifier: process, state: .exited(.exited(0))),
        ])
    var session = DebugSession(debuggee: debuggee)
    session.state = .exited(.launched, .exited(0))
    try session.close(cause: .normal)
    #expect(session.debuggee.processes.isEmpty)
    guard case .absent = session.state else {
      Issue.record("closed session retained lifecycle state")
      return
    }
  }

  @Test
  internal func debuggee() throws {
    let parent =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 9),
                                thread: ThreadIdentifier(rawValue: 4))
    let child =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 10),
                                thread: ThreadIdentifier(rawValue: 1))
    var store = Debuggee()
    store.observe(.started(parent))
    store.observe(.forked(Debuggee.Fork(parent: parent, child: child,
                                        vfork: false)))
    #expect(store.parent(child.process) == parent.process)
    #expect(store.contains(child))

    let actions = [
      Debuggee.Continuation(selection: .process(child.process),
                            operation: .step),
    ]
    try store.prepare(actions.span)
    store.resume(actions.span)
    if case .stepping = store.state(child) {
    } else {
      Issue.record("thread is not stepping")
    }
    store.insert(child)
    if case .stepping = store.state(child) {
    } else {
      Issue.record("thread refresh replaced its state")
    }
  }

  @Test
  internal func refresh() {
    let process = ProcessIdentifier(rawValue: 9)
    let first =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 1))
    let second =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 2))
    var store = Debuggee()
    store.observe(.started(first))
    store.observe(.started(second))
    let threads = [second]
    store.refresh(process, threads: threads.span)
    #expect(store.contains(first) == false)
    #expect(store.contains(second))
  }

  @Test
  internal func selection() {
    let process = ProcessIdentifier(rawValue: 9)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 1))
    var store = Debuggee()
    store.observe(.started(thread))
    let threads = Array<ProcessThreadIdentifier>()
    store.refresh(process, threads: threads.span)
    let selected =
        GDBPacketScope.thread(.thread(thread), fallback: thread,
                              debuggee: store)
    #expect(selected == nil)
  }

  @Test
  internal func validation() {
    let process = ProcessIdentifier(rawValue: 9)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 4))
    let debuggee =
        Debuggee.Process(identifier: process, state: .stopped,
                         threads: [Debuggee.Thread(identifier: thread)])
    let store = Debuggee(processes: [debuggee])
    let conflict = [
      Debuggee.Continuation(selection: .thread(thread), operation: .resume),
      Debuggee.Continuation(selection: .thread(thread), operation: .step),
    ]
    #expect(throws: Debuggee.Error.state) {
      try store.prepare(conflict.span)
    }
    let missing = ProcessIdentifier(rawValue: process.rawValue + 1)
    let unmatched = [
      Debuggee.Continuation(selection: .process(missing), operation: .resume),
    ]
    #expect(throws: Debuggee.Error.thread) {
      try store.prepare(unmatched.span)
    }
  }
}

@Suite
internal struct DebuggeeContinuationPlanTests {
  @Test
  internal func precedence() throws {
    let process = ProcessIdentifier(rawValue: 1)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 2))
    let actions = [
      Debuggee.Continuation(selection: .all, operation: .resume),
      Debuggee.Continuation(selection: .process(process), operation: .step),
      Debuggee.Continuation(selection: .thread(thread), operation: .stop),
    ]
    let selected =
        try Debuggee.Continuation.Plan.resolve(thread, actions: actions.span)
    #expect(selected == actions[2])
    let fallback =
        try Debuggee.Continuation.Plan.fallback(process, actions: actions.span)
    #expect(fallback == actions[1])
  }

  @Test
  internal func unmatched() throws {
    let process = ProcessIdentifier(rawValue: 1)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 2))
    let other =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 3),
                                thread: ThreadIdentifier(rawValue: 4))
    let actions = [
      Debuggee.Continuation(selection: .thread(other), operation: .resume),
    ]
    let resolved =
        try Debuggee.Continuation.Plan.resolve(thread, actions: actions.span)
    let fallback =
        try Debuggee.Continuation.Plan.fallback(process, actions: actions.span)
    #expect(resolved == nil)
    #expect(fallback == nil)
  }

  @Test
  internal func conflict() {
    let process = ProcessIdentifier(rawValue: 1)
    let thread =
        ProcessThreadIdentifier(process: process,
                                thread: ThreadIdentifier(rawValue: 2))
    let actions = [
      Debuggee.Continuation(selection: .thread(thread), operation: .resume),
      Debuggee.Continuation(selection: .thread(thread), operation: .step),
    ]
    #expect(throws: Debuggee.Error.state) {
      try Debuggee.Continuation.Plan.resolve(thread, actions: actions.span)
    }
  }
}
