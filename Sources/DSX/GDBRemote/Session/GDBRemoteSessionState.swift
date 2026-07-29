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
  internal var stops: GDBRemoteNotifications
  internal var output: GDBRemoteNotifications
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
    stops = GDBRemoteNotifications()
    output = GDBRemoteNotifications()
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
