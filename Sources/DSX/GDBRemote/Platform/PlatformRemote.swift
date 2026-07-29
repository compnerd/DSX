// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct PlatformRemote: ~Copyable, Sendable {
  internal var core: GDBRemoteCore
  internal var session: PlatformSession
  private var closed = false

  internal var complete: Bool {
    core.complete
  }

  internal init(channel: consuming ConnectionTransport,
                session: consuming PlatformSession,
                compatibility: CompatibilityMode) {
    self.session = consume session
    core = GDBRemoteCore(channel: consume channel, compatibility: compatibility,
                         features: [.noack, .echo],
                         capacity: Tuning.Packet.capacity)
  }

  internal mutating func step() throws(GDBRemoteError) {
    do throws(GDBRemoteError) {
      if session.servers.isEmpty == false {
        let result =
            try session.servers.wait { timeout, events throws(GDBRemoteError) in
          try core.channel.wait(timeout: timeout, events: events)
        }
        if result != .channel {
          return session.reap()
        }
      }
      try packet()
      session.reap()
    } catch {
      switch error {
      case .capacity, .closed, .transport:
        close()
        throw error
      case .framing, .handler:
        throw error
      }
    }
  }

  private mutating func packet() throws(GDBRemoteError) {
    guard let exchange =
        try core.packet({ match, data, state, sink throws(GDBHandlerError) in
      switch match.route {
      case .remote:
        return try state.handle(match.leaf, payload: data, writer: &sink)
      case .session:
        session.reap()
        return try session.launch.handle(match.leaf, payload: data,
                                         files: &session.files, relative: true,
                                         writer: &sink)
      case .mode:
        return try session.handle(match.leaf, payload: data, writer: &sink)
      case .unsupported:
        throw .unsupported
      }
    }) else {
      return
    }
    guard try core.acknowledge(exchange.message,
                               enabled: exchange.acknowledge) else {
      return
    }
    try core.finish(exchange.result, interrupt: exchange.message == .interrupt)
  }

  internal mutating func close() {
    if closed {
      return
    }
    closed = true
    do throws(Debuggee.Error) {
      try session.close()
    } catch {
      error.log("failed to release session resources", level: .critical,
                channel: .system)
    }
  }
}
