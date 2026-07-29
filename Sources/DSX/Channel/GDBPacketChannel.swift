// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal typealias GDBPacketReceiver =
    (GDBChannelMessage, GDBPacketMatch, borrowing Span<UInt8>,
     inout GDBPacketBuffer) -> Void
internal typealias GDBResponse =
    (inout GDBPacketWriter) throws(GDBHandlerError) -> Void

internal enum GDBChannelMessage: Sendable {
  case acknowledge
  case interrupt
  case packet
  case reject
}

internal struct GDBPacketBuffer: ~Copyable, Sendable {
  fileprivate var output: Array<UInt8>

  fileprivate init(capacity: Int) {
    output = []
    output.reserveCapacity(capacity)
  }

  internal mutating func prepare() {
    output.removeAll(keepingCapacity: true)
    frame(.text)
  }

  internal mutating func response(_ capacity: Int, encoding: GDBPacketEncoding,
                                  limit: Int? = nil, _ body: GDBResponse)
      -> Result<Void, GDBHandlerError> {
    var capacity = capacity
    while true {
      output.removeAll(keepingCapacity: true)
      var failure: GDBHandlerError?
      output.append(addingCapacity: capacity) { output in
        var writer = GDBPacketWriter(consume output)
        do throws(GDBHandlerError) {
          try body(&writer)
        } catch {
          failure = error
        }
        output = writer.finish()
      }
      guard let failure else {
        frame(encoding)
        return .success(())
      }
      guard case .capacity = failure, let limit, capacity < limit else {
        return .failure(failure)
      }
      capacity = min(capacity * 2, limit)
    }
  }

  private mutating func frame(_ encoding: GDBPacketEncoding) {
    DSX.log(output.span, channel: .packet, direction: .outgoing)
    let raw = output.count
    let count = GDBPacketFraming.capacity(output.span, encoding: encoding)
    for _ in raw ..< count {
      output.append(0)
    }
    var buffer = output.mutableSpan
    GDBPacketFraming.frame(raw, encoding: encoding, output: &buffer)
  }

  internal mutating func notification() {
    guard !output.isEmpty else {
      return
    }
    output[0] = UInt8(ascii: "%")
  }
}

internal struct GDBPacketChannel<Channel: ByteChannel & ~Copyable>:
    ~Copyable, Sendable {
  private var channel: Channel
  private let capacity: Int
  private var buffer: GDBPacketBuffer
  private var cursor: Int
  private var data: Array<UInt8>

  internal init(channel: consuming Channel,
                capacity: Int = Configuration.PacketCapacity) {
    precondition(capacity > 0)
    let framed = GDBPacketFraming.capacity(capacity)
    self.channel = consume channel
    self.capacity = framed
    buffer = GDBPacketBuffer(capacity: framed)
    cursor = 0
    data = []
    data.reserveCapacity(framed)
  }

  internal mutating func receive(checksum: Bool = true,
                                 _ body: GDBPacketReceiver)
      throws(GDBRemoteError) {
    while true {
      let frame: GDBPacketFrame?
      do {
        var data = data.mutableSpan
        frame = try GDBPacketFraming.extract(&data, cursor: &cursor,
                                             checksum: checksum)
      } catch {
        throw .framing(error)
      }
      if let frame {
        let range: Range<Int>
        let message: GDBChannelMessage
        switch frame {
        case .control(let control):
          range = control
          let marker = data[control.lowerBound]
          if marker == UInt8(ascii: "-") {
            try send()
          }
          message = switch marker {
          case UInt8(ascii: "+"): .acknowledge
          case UInt8(ascii: "-"): .reject
          case 0x03: .interrupt
          default: preconditionFailure("invalid control byte")
          }
        case .packet(let packet):
          range = packet
          message = .packet
        }
        let match = GDBPacketClassifier.classify(data.span.extracting(range))
        let logical = try decode(range, encoding: match.request)
        let packet = data.span.extracting(logical)
        return body(message, match, packet, &buffer)
      }

      if cursor > 0 {
        if cursor == data.count {
          data.removeAll(keepingCapacity: true)
        } else {
          data.removeFirst(cursor)
        }
        cursor = 0
      }

      let free = capacity - data.count
      guard free > 0 else {
        throw .capacity
      }
      var count = 0
      do throws(TransportError) {
        try data.append(addingCapacity: free) { buffer throws(TransportError) in
          try channel.read(into: &buffer)
          count = buffer.count
        }
      } catch {
        throw .transport(error)
      }
      guard count > 0 else {
        throw .closed
      }
    }
  }

  private mutating func decode(_ range: Range<Int>, encoding: GDBPacketEncoding)
      throws(GDBRemoteError) -> Range<Int> {
    do {
      var input = data.mutableSpan
      return try GDBPacketFraming.decode(range, input: &input,
                                         encoding: encoding)
    } catch {
      throw .framing(error)
    }
  }

  internal borrowing func wait(_ timeout: Int32,
                               events: borrowing Span<WaitHandle>)
      throws(GDBRemoteError) -> WaitResult {
    if cursor < data.count {
      return .channel
    }
    do {
      return try channel.wait(timeout, events: events)
    } catch {
      throw .transport(error)
    }
  }

  internal mutating func response(_ capacity: Int, encoding: GDBPacketEncoding,
                                  limit: Int? = nil, _ body: GDBResponse)
      -> Result<Void, GDBHandlerError> {
    buffer.response(capacity, encoding: encoding, limit: limit, body)
  }

  internal mutating func respond(_ capacity: Int, encoding: GDBPacketEncoding,
                                 _ body: GDBResponse) throws(GDBRemoteError) {
    let result = buffer.response(capacity, encoding: encoding, body)
    if case .failure(let error) = result {
      throw .handler(error)
    }
  }

  internal mutating func prepare() {
    buffer.prepare()
  }

  internal mutating func notification() {
    buffer.notification()
  }

  internal mutating func signal(_ byte: UInt8) throws(GDBRemoteError) {
    let bytes: InlineArray<1, UInt8> = [byte]
    try transfer(&channel, bytes.span)
  }

  internal mutating func send() throws(GDBRemoteError) {
    try transfer(&channel, buffer.output.span)
  }
}

private func transfer<Channel>(_ channel: inout Channel,
                               _ bytes: borrowing Span<UInt8>)
    throws(GDBRemoteError) where Channel: ByteChannel & ~Copyable {
  var offset = 0
  while offset < bytes.count {
    let count: Int
    do {
      let remaining = bytes.extracting(offset...)
      count = try channel.write(remaining)
    } catch {
      throw .transport(error)
    }
    guard count > 0 else {
      throw .closed
    }
    offset += count
  }
}
