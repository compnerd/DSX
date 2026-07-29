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

    internal var origin: Origin? {
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
  internal var deferred = Array<Debuggee.Event>()
  internal var error: Debuggee.Error?
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

extension DebugSession {
  internal var origin: Origin? {
    state.origin
  }
}
