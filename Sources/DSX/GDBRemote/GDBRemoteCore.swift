// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal typealias GDBPacketHandler =
    (GDBPacketMatch, borrowing Span<UInt8>, inout GDBRemoteSessionState,
     inout GDBPacketWriter) throws(GDBHandlerError) -> GDBPacketDisposition

internal typealias GDBPacketExchange =
    (message: GDBChannelMessage, acknowledge: Bool,
     disposition: GDBPacketDisposition, failure: GDBHandlerError?)

internal struct GDBRemoteCore<Channel: ByteChannel & ~Copyable>:
    ~Copyable, Sendable {
  internal var channel: GDBPacketChannel<Channel>
  internal var state: GDBRemoteSessionState
  internal private(set) var complete: Bool

  internal init(channel: consuming Channel, compatibility: CompatibilityMode,
                features: GDBRemoteFeatures,
                capacity: Int = Configuration.PacketCapacity) {
    precondition(capacity > 0)
    self.channel = GDBPacketChannel(channel: consume channel,
                                    capacity: capacity)
    state = GDBRemoteSessionState(compatibility: compatibility,
                                  features: features, capacity: capacity)
    complete = false
  }

  internal mutating func packet(_ body: GDBPacketHandler) throws(GDBRemoteError)
      -> GDBPacketExchange? {
    var acknowledge = false
    var disposition = GDBPacketDisposition.none
    var failure: GDBHandlerError?
    var message = GDBChannelMessage.packet
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
        let limit = match.leaf == .libraries ? Configuration.PacketLimit : nil
        let result = reply.response(capacity, encoding: match.response,
                                    limit: limit,
                                    { writer throws(GDBHandlerError) in
          guard GDBPacketClassifier.allows(match, state) else {
            throw .unsupported
          }
          let payload = data.extracting(match.payload...)
          disposition = try body(match, payload, &state, &writer)
        })
        if case .failure(let error) = result {
          failure = error
        }
      }
    } catch {
      switch error {
      case .framing(let error):
        try recover(error)
        return nil
      case .capacity, .closed, .handler, .transport:
        throw error
      }
    }
    return (message: message, acknowledge: acknowledge,
            disposition: disposition, failure: failure)
  }

  internal mutating func finish(_ disposition: GDBPacketDisposition,
                                failure: GDBHandlerError?,
                                interrupt: Bool = false)
      throws(GDBRemoteError) {
    if let failure {
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
      case .code(let code):
        try finish(error: code)
      case .debuggee(.access):
        try finish(error: GDBErrorCode.access, failure: failure)
      case .malformed:
        try finish(error: GDBErrorCode.invalid, failure: failure)
      case .debuggee:
        try finish(error: GDBErrorCode.failure, failure: failure)
      }
      return
    }
    try finish(disposition)
  }

  internal mutating func finish(_ disposition: GDBPacketDisposition)
      throws(GDBRemoteError) {
    switch disposition {
    case .close:
      try channel.send()
      complete = true
    case .none:
      break
    case .reply:
      try channel.send()
    }
  }

  private mutating func finish(error code: UInt8,
                               failure: GDBHandlerError? = nil)
      throws(GDBRemoteError) {
    let capacity = state.negotiation.capacity
    try channel.respond(capacity, encoding: .text,
                        { writer throws(GDBHandlerError) in
      try writer.error(code)
      if state.messages, case .debuggee(let error) = failure {
        try writer.append(UInt8(ascii: ";"))
        try writer.encoded(error.message)
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
                                     _ enabled: Bool) throws(GDBRemoteError)
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
