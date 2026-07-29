// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBRemoteEnumeration: ~Copyable, Sendable {
  internal var processes: GDBProcessEnumeration?
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
  internal var stops: GDBRemoteNotifications
  internal var output: GDBRemoteNotifications
  internal var messages: Bool
  internal var termination: GDBRemoteTermination
  internal var events: Bool
  internal var options: GDBRemoteThreadOptions
  internal var interruption: ProcessIdentifier?

  internal init(compatibility: CompatibilityMode,
                features: GDBRemoteFeatures = [.noack],
                capacity: Int = Tuning.Packet.capacity,
                selection: GDBRemoteSelection = GDBRemoteSelection()) {
    self.compatibility = compatibility
    negotiation = GDBRemoteNegotiation(supported: features, capacity: capacity)
    self.selection = selection
    delivery = SignalSet()
    modules = true
    nonstop = false
    stops = GDBRemoteNotifications()
    output = GDBRemoteNotifications()
    messages = false
    termination = .none
    events = false
    options = GDBRemoteThreadOptions()
    interruption = nil
  }

  internal mutating func observe(_ event: borrowing Debuggee.Event) {
    switch event {
    case let .executed(thread):
      modules = true
      selection = GDBRemoteSelection(stopped: thread)
      options.remove(thread.process)
    case .image:
      modules = true
    case let .stopped(stop):
      selection.stopped = stop.thread
    case let .exited(process, _):
      if selection.stopped?.process == process {
        selection.stopped = nil
      }
    case let .terminated(thread, _):
      options.remove(thread)
      if selection.stopped == thread {
        selection.stopped = nil
      }
    case let .forked(fork):
      selection.stopped = fork.parent
    case .output, .started:
      break
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
    case let .legacy(identifier), let .extended(identifier):
      guard identifier == process else {
        return .none
      }
    }
    let termination = self
    self = .none
    return termination
  }
}
