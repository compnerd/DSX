// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBRemoteEnumeration: ~Copyable, Sendable {
  internal var processes: NativeProcessCursor?
  internal var filter: String?
  internal var thread: Int?
}

internal struct GDBRemoteSessionState: ~Copyable, Sendable {
  internal let compatibility: CompatibilityMode
  internal var negotiation: GDBRemoteNegotiation
  internal var selection: GDBRemoteSelection
  internal var enumeration = GDBRemoteEnumeration()
  internal var delivery: SignalSet
  internal var modules: Bool
  internal var nonstop: Bool
  internal var stops: GDBRemoteStops
  internal var messages: Bool
  internal var termination: GDBRemoteTermination
  internal var events: Bool
  internal var options: GDBRemoteThreadOptions

  internal init(compatibility: CompatibilityMode,
                features: GDBRemoteFeatures = [.noack],
                capacity: Int = Configuration.PacketCapacity,
                selection: GDBRemoteSelection = GDBRemoteSelection()) {
    self.compatibility = compatibility
    negotiation = GDBRemoteNegotiation(supported: features, capacity: capacity)
    self.selection = selection
    delivery = SignalSet()
    modules = true
    nonstop = false
    stops = GDBRemoteStops()
    messages = false
    termination = .none
    events = false
    options = GDBRemoteThreadOptions()
  }

  internal mutating func observe(_ event: borrowing Debuggee.Event) {
    switch event {
    case .executed(let thread):
      modules = true
      selection = GDBRemoteSelection(stopped: thread)
      options.remove(thread.process)
    case .image:
      modules = true
    case .stopped(let stop):
      selection.stopped = stop.thread
    case .exited(let process, _):
      if selection.stopped?.process == process {
        selection.stopped = nil
      }
    case .terminated(let thread, _):
      options.remove(thread)
      if selection.stopped == thread {
        selection.stopped = nil
      }
    case .forked(let fork):
      selection.stopped = fork.parent
    case .output, .started:
      break
    }
  }
}

internal struct GDBRemoteThreadOptions: Sendable {
  private typealias Record = (thread: ProcessThreadIdentifier, options: UInt64)

  private var records = Array<Record>()

  internal mutating func set(_ selection: Debuggee.Thread.Selection,
                             options: UInt64, debuggee: borrowing Debuggee) {
    for process in debuggee.processes {
      for thread in process.threads
          where applies(selection, thread: thread.identifier) {
        assign(thread.identifier, options: options)
      }
    }
  }

  internal borrowing func contains(_ thread: ProcessThreadIdentifier,
                                   option: UInt64) -> Bool {
    for record in records where record.thread == thread {
      return record.options & option == option
    }
    return false
  }

  internal mutating func remove(_ thread: ProcessThreadIdentifier) {
    records.removeAll { record in
      record.thread == thread
    }
  }

  internal mutating func remove(_ process: ProcessIdentifier) {
    records.removeAll { record in
      record.thread.process == process
    }
  }

  private mutating func assign(_ thread: ProcessThreadIdentifier,
                               options: UInt64) {
    for index in records.indices where records[index].thread == thread {
      records[index].options = options
      return
    }
    records.append((thread: thread, options: options))
  }

  private borrowing func applies(_ selection: Debuggee.Thread.Selection,
                                 thread: ProcessThreadIdentifier) -> Bool {
    switch selection {
    case .all, .any: true
    case .process(let process): process == thread.process
    case .thread(let selected): selected == thread
    }
  }
}

internal enum GDBRemoteTermination: Sendable {
  case none
  case legacy(ProcessIdentifier)
  case extended(ProcessIdentifier)

  internal mutating func take(_ process: ProcessIdentifier) -> Self {
    switch self {
    case .none:
      return .none
    case .legacy(let identifier), .extended(let identifier):
      guard identifier == process else {
        return .none
      }
    }
    let termination = self
    self = .none
    return termination
  }
}

/// Stop-time replies, including the notification awaiting vStopped.
internal struct GDBRemoteStops: Sendable {
  private var replies = Array<Array<UInt8>>()
  private var cursor = 0

  internal var first: Array<UInt8>? {
    cursor < replies.count ? replies[cursor] : nil
  }

  internal mutating func reset() {
    replies.removeAll(keepingCapacity: true)
    cursor = 0
  }

  internal mutating func restart() {
    // A new ? snapshot must preserve unacknowledged process exits.
    replies.removeFirst(cursor)
    replies.removeAll { reply in
      reply.first != UInt8(ascii: "W") && reply.first != UInt8(ascii: "X")
    }
    cursor = 0
  }

  internal mutating func record(_ reply: borrowing Span<UInt8>) {
    replies.append(reply.withUnsafeBufferPointer { Array($0) })
  }

  internal mutating func next() -> Array<UInt8>? {
    guard cursor < replies.count else {
      return nil
    }
    // Release acknowledged payloads even while new reports keep arriving.
    replies[cursor] = []
    cursor += 1
    if cursor >= replies.count {
      reset()
      return nil
    }
    if cursor >= replies.count / 2 {
      replies.removeFirst(cursor)
      cursor = 0
    }
    return first
  }
}
