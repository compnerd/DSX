// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemote {
  private static let polling = Duration.milliseconds(100)

  internal mutating func packet() throws(GDBRemoteError) {
    let exchange: GDBPacketExchange
    do throws(GDBRemoteError) {
      guard let result =
          try core.packet({ match, data, state, sink throws(GDBHandlerError) in
        let disposition = switch match.route {
        case .remote:
          try state.handle(match.leaf, payload: data, writer: &sink)
        case .session:
          try session.launch.handle(match.leaf, payload: data,
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
          let libraries = state.negotiation.enabled.contains(.libraries)
          session.control.libraries(libraries)
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

    guard try core.acknowledge(exchange.message,
                               enabled: exchange.acknowledge) else {
      return
    }

    if case .waiting = session.phase {
      try wait()
      if case .waiting = session.phase {
        return
      }
    }

    try core.finish(exchange.result, interrupt: exchange.message == .interrupt)
  }

  private mutating func wait() throws(GDBRemoteError) {
    while case .waiting = session.phase {
      let result =
          try core.channel.wait(timeout: GDBRemote.polling, events: Span())
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
          return try core.finish(.failure(.code(GDBErrorCode.unavailable)))
        }
      }
      do throws(Debuggee.Error) {
        try session.poll()
      } catch {
        session.cancel()
        return try core.finish(.failure(.debuggee(error)))
      }
    }
  }
}
