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
    let count = encoding.capacity(output.span)
    for _ in raw ..< count {
      output.append(0)
    }
    var buffer = output.mutableSpan
    var checksum: UInt8 = 0
    var source = raw
    var destination = count - 3
    // The exact frame size is already known. Sum the wire bytes while moving
    // backward, so expansion never overwrites unread payload bytes.
    while source > 0 {
      source -= 1
      let byte = buffer[source]
      if encoding.escapes(byte) {
        destination -= 2
        buffer[destination] = UInt8(ascii: "}")
        buffer[destination + 1] = byte ^ 0x20
        checksum &+= UInt8(ascii: "}")
        checksum &+= byte ^ 0x20
      } else {
        destination -= 1
        buffer[destination] = byte
        checksum &+= byte
      }
    }
    buffer[0] = UInt8(ascii: "$")
    buffer[count - 3] = UInt8(ascii: "#")
    buffer[count - 2] = (checksum >> 4).hexadecimal
    buffer[count - 1] = checksum.hexadecimal
  }

  internal mutating func notification() {
    guard !output.isEmpty else {
      return
    }
    output[0] = UInt8(ascii: "%")
  }
}

internal struct GDBPacketChannel: ~Copyable, Sendable {
  private let channel: ConnectionTransport
  private let capacity: Int
  private var buffer: GDBPacketBuffer
  private var cursor: Int
  private var data: Array<UInt8>
  private var incomplete = false

  @inline(__always)
  internal init(channel: consuming ConnectionTransport,
                capacity: Int = Configuration.PacketCapacity) {
    precondition(capacity > 0)
    let framed = GDBPacketEncoding.binary.capacity(capacity)
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
    var received = false
    while true {
      let frame: GDBPacketFrame?
      do {
        frame =
            try GDBPacketFrame(data.span, cursor: &cursor, checksum: checksum)
      } catch {
        incomplete = false
        throw .framing(error)
      }
      if let frame {
        incomplete = false
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
        let match = GDBPacketMatch(data.span.extracting(range))
        let logical = try decode(range, encoding: match.request)
        let packet = data.span.extracting(logical)
        return body(message, match, packet, &buffer)
      }

      incomplete = true
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
      if received {
        return
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
      received = true
    }
  }

  private mutating func decode(_ range: Range<Int>, encoding: GDBPacketEncoding)
      throws(GDBRemoteError) -> Range<Int> {
    do {
      var input = data.mutableSpan
      return try input.decode(range, encoding: encoding)
    } catch {
      throw .framing(error)
    }
  }

  internal borrowing func wait(timeout: Int32,
                               events: borrowing Span<WaitHandle>)
      throws(GDBRemoteError) -> WaitResult {
    if cursor < data.count, incomplete == false {
      return .channel
    }
    do {
      return try channel.wait(timeout: timeout, events: events)
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

  internal borrowing func signal(_ byte: UInt8) throws(GDBRemoteError) {
    let bytes: InlineArray<1, UInt8> = [byte]
    try channel.transfer(bytes.span)
  }

  internal borrowing func send() throws(GDBRemoteError) {
    try channel.transfer(buffer.output.span)
  }
}

extension ConnectionTransport {
  fileprivate borrowing func transfer(_ bytes: borrowing Span<UInt8>)
      throws(GDBRemoteError) {
    var offset = 0
    while offset < bytes.count {
      let count: Int
      do {
        let remaining = bytes.extracting(offset...)
        count = try write(remaining)
      } catch {
        throw .transport(error)
      }
      guard count > 0 else {
        throw .closed
      }
      offset += count
    }
  }
}
