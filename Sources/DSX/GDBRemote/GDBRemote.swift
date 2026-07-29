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
                capacity: Int = Configuration.PacketCapacity) {
    self.session = consume session
    closed = false
    let features = GDBRemoteFeatures(DebugCapabilities.current)
    core = GDBRemoteCore(channel: consume channel, compatibility: compatibility,
                         features: features, capacity: capacity)
  }

  internal mutating func step() throws(GDBRemoteError) {
    if case .pending = session.phase {
      let interval =
          NativeDebugControl.interval ?? Configuration.DebuggeePollInterval
      let result: WaitResult
      do throws(GDBRemoteError) {
        result = try core.channel.wait(interval, events: Span())
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
    while try event() {
    }
  }

  private mutating func event() throws(GDBRemoteError) -> Bool {
    let event: Debuggee.Event?
    do throws(Debuggee.Error) {
      event = try session.next(state: core.state)
    } catch {
      DSX.log("failed to process debuggee event: \(error)", level: .error,
              channel: .process)
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
      DSX.log("failed to release session resources: \(error)", level: .critical,
              channel: .system)
    }
  }
}
