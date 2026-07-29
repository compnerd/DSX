// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemote where Channel: ~Copyable {
  internal mutating func packet() throws(GDBRemoteError) {
    let exchange: GDBPacketExchange
    do throws(GDBRemoteError) {
      guard let result =
          try core.packet({ match, data, state, sink throws(GDBHandlerError) in
        let disposition = switch match.route {
        case .remote:
          try GDBCommonRouter.remote(match.leaf, payload: data, state: &state,
                                     writer: &sink)
        case .session:
          try GDBCommonRouter.session(match.leaf, payload: data,
                                      launch: &session.launch,
                                      files: &session.files, relative: false,
                                      writer: &sink)
        case .mode:
          try session.handle(match.leaf, payload: data, state: &state,
                             writer: &sink)
        case .unsupported:
          try session.handle(.unsupported, payload: data, state: &state,
                             writer: &sink)
        }
        if match.leaf == .supported {
          session.libraries(state.negotiation.enabled.contains(.libraries))
        }
        return disposition
      }) else {
        return
      }
      exchange = result
    } catch {
      switch error {
      case .capacity, .closed, .transport:
        close(.failure)
        throw error
      case .framing, .handler:
        throw error
      }
    }

    guard try core.acknowledge(exchange.message, exchange.acknowledge) else {
      return
    }

    if case .waiting = session.phase {
      try wait()
      if case .waiting = session.phase {
        return
      }
    }

    try core.finish(exchange.disposition, failure: exchange.failure,
                    interrupt: exchange.message == .interrupt)
  }

  private mutating func wait() throws(GDBRemoteError) {
    while case .waiting = session.phase {
      let result = try core.channel.wait(Configuration.AttachWaitInterval,
                                         events: Span())
      if result == .channel {
        var interrupt = false
        do throws(GDBRemoteError) {
          let validate = core.state.negotiation.acknowledgements
          try core.channel.receive(checksum: validate) { message, _, _, _ in
            if case .interrupt = message {
              interrupt = true
            }
          }
        } catch {
          close(.failure)
          throw error
        }
        if interrupt {
          session.cancel()
          return try core.finish(.none,
                                 failure: .code(GDBErrorCode.unavailable))
        }
        continue
      }
      do throws(Debuggee.Error) {
        try session.poll()
      } catch {
        session.cancel()
        return try core.finish(.none, failure: .debuggee(error))
      }
    }
  }
}
