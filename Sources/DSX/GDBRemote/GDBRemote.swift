// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBRemoteError: Error {
  case capacity
  case closed
  case framing(GDBPacketError)
  case handler(GDBHandlerError)
  case transport(TransportError)
}

internal struct GDBRemote: ~Copyable, Sendable {
  internal var core: GDBRemoteCore
  internal var session: DebugSession
  private var closed: Bool

  internal var complete: Bool {
    core.complete
  }

  internal init(channel: consuming ConnectionTransport,
                session: consuming DebugSession,
                compatibility: CompatibilityMode,
                capacity: Int = Tuning.Packet.capacity) {
    self.session = consume session
    closed = false
    let features = GDBRemoteFeatures(DebugCapabilities.current)
    core = GDBRemoteCore(channel: consume channel, compatibility: compatibility,
                         features: features, capacity: capacity)
  }

  internal mutating func step(events: borrowing NativeEventSource =
                                  NativeEventSource()) throws(GDBRemoteError) {
    if case .pending = session.phase {
      if events.polling == false {
        // Acknowledge the wakeup before checking statuses. A later native
        // transition must remain readable when we enter the transport wait.
        do throws(Debuggee.Error) {
          try events.drain()
        } catch {
          close(.failure)
          throw .handler(.debuggee(error))
        }
        // Service control input already received before publishing a stop.
        // Otherwise a simultaneous Ctrl-C becomes a new, queued interrupt
        // after the stop reply, rather than completing the current run.
        if try core.channel.wait(timeout: .zero, events: Span()) == .channel {
          try packet()
          _ = try event()
          return
        }
        if try event() {
          return
        }
      }
      let result: WaitResult
      do throws(GDBRemoteError) {
        result = try events.wait(session.control,
                                 { delay, fds throws(GDBRemoteError) in
          try core.channel.wait(timeout: delay, events: fds)
        })
      } catch {
        close(.failure)
        throw error
      }
      if case .channel = result {
        try packet()
      }
    } else {
      try packet()
    }
    if events.polling {
      while try event() {
      }
    } else {
      _ = try event()
    }
  }

  private mutating func event() throws(GDBRemoteError) -> Bool {
    let event: Debuggee.Event?
    do throws(Debuggee.Error) {
      if let process = core.state.interruption {
        switch session.debuggee.state(process) {
        case .running?:
          _ = try session.interrupt(process)
          core.state.interruption = nil
        case .stopped?:
          break
        default:
          core.state.interruption = nil
        }
      }
      event = try session.next(state: core.state)
    } catch {
      error.log("failed to process debuggee event")
      throw .handler(.debuggee(error))
    }
    guard let event else {
      return false
    }
    try handle(event: consume event)
    return true
  }

  internal mutating func close(_ cause: SessionClosure) {
    if closed {
      return
    }
    closed = true
    do throws(Debuggee.Error) {
      try session.close(cause: cause)
    } catch {
      error.log("failed to release session resources", level: .critical,
                channel: .system)
    }
  }
}
