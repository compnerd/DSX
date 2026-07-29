// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal typealias GDBPacketHandler =
    (GDBPacketMatch, borrowing Span<UInt8>, inout GDBRemoteSessionState,
     inout GDBPacketWriter) throws(GDBHandlerError) -> GDBPacketDisposition

internal typealias GDBPacketExchange =
    (message: GDBChannelMessage, acknowledge: Bool,
     result: Result<GDBPacketDisposition, GDBHandlerError>)

internal struct GDBRemoteCore: ~Copyable, Sendable {
  /// Maximum library reply size in bytes.
  private static let limit = 4_194_304

  internal var channel: GDBPacketChannel
  internal var state: GDBRemoteSessionState
  internal private(set) var complete: Bool

  internal init(channel: consuming ConnectionTransport,
                compatibility: CompatibilityMode, features: GDBRemoteFeatures,
                capacity: Int = Tuning.Packet.capacity) {
    precondition(capacity > 0)
    self.channel =
        GDBPacketChannel(channel: consume channel, capacity: capacity)
    state = GDBRemoteSessionState(compatibility: compatibility,
                                  features: features, capacity: capacity)
    complete = false
  }

  internal mutating func packet(_ body: GDBPacketHandler) throws(GDBRemoteError)
      -> GDBPacketExchange? {
    var acknowledge = false
    var result = Result<GDBPacketDisposition, GDBHandlerError>.success(.none)
    var message: GDBChannelMessage?
    do throws(GDBRemoteError) {
      let checksum = state.negotiation.acknowledgements
      try channel.receive(checksum: checksum) { event, match, data, reply in
        message = event
        DSX.log(data, channel: .packet, direction: .incoming)
        switch event {
        case .acknowledge, .reject:
          return
        case .interrupt, .packet:
          break
        }
        let interrupt = switch event {
        case .interrupt: true
        case .acknowledge, .packet, .reject: false
        }
        acknowledge = if interrupt {
          false
        } else {
          state.negotiation.acknowledgements || match.leaf == .QStartNoAckMode
        }
        let capacity = state.negotiation.payload
        let limit = match.leaf == .libraries ? GDBRemoteCore.limit : nil
        result = reply.response(capacity, encoding: match.response,
                                limit: limit,
                                { writer throws(GDBHandlerError) in
          guard state.allows(match) else {
            throw .unsupported
          }
          let payload = data.extracting(match.payload...)
          return try body(match, payload, &state, &writer)
        })
      }
    } catch {
      switch error {
      case let .framing(error):
        try recover(error)
        return nil
      case .capacity, .closed, .handler, .transport:
        throw error
      }
    }
    guard let message else {
      return nil
    }
    return (message: message, acknowledge: acknowledge, result: result)
  }

  internal mutating func finish(_ result: Result<GDBPacketDisposition,
                                                 GDBHandlerError>,
                                interrupt: Bool = false)
      throws(GDBRemoteError) {
    switch result {
    case let .failure(failure):
      switch failure {
      case .unexpected:
        throw .handler(failure)
      case .capacity:
        try finish(error: GDBErrorCode.failure)
      case .unsupported, .debuggee(.unsupported):
        guard interrupt else {
          channel.prepare()
          return try channel.send()
        }
      case let .code(code):
        try finish(error: code)
      case .debuggee(.access):
        try finish(error: GDBErrorCode.access, failure: failure)
      case .malformed:
        try finish(error: GDBErrorCode.invalid, failure: failure)
      case .debuggee:
        try finish(error: GDBErrorCode.failure, failure: failure)
      }
    case .success(.none):
      break
    case let .success(disposition):
      try channel.send()
      if disposition == .close {
        complete = true
      }
    }
  }

  private mutating func finish(error code: UInt8,
                               failure: GDBHandlerError? = nil)
      throws(GDBRemoteError) {
    let capacity = state.negotiation.payload
    let messages = state.messages
    try channel.respond(capacity, encoding: .text,
                        { writer throws(GDBHandlerError) in
      try writer.error(code)
      if messages, case let .debuggee(error) = failure {
        let message = error.message
        guard writer.output.freeCapacity > 0,
            message.utf8.count <= (writer.output.freeCapacity - 1) / 2 else {
          return
        }
        try writer.append(UInt8(ascii: ";"))
        try writer.encoded(message)
      }
    })
    try channel.send()
  }

  internal mutating func recover(_ error: GDBPacketError)
      throws(GDBRemoteError) {
    DSX.log("discarding malformed packet: \(error)", level: .warning,
            channel: .packet)
    guard state.negotiation.acknowledgements else {
      return
    }
    try channel.signal(UInt8(ascii: "-"))
  }

  internal mutating func acknowledge(_ message: GDBChannelMessage,
                                     enabled: Bool) throws(GDBRemoteError)
      -> Bool {
    switch message {
    case .acknowledge, .reject:
      return false
    case .interrupt, .packet:
      if enabled {
        try channel.signal(UInt8(ascii: "+"))
      }
      return true
    }
  }
}
