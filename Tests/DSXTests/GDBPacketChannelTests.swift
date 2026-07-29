// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct GDBPacketChannelTests {
  @Test(arguments: [WaitResult.channel, .event, .timeout])
  internal func readiness(_ result: WaitResult) throws(GDBRemoteError) {
    let channel = GDBPacketChannel(channel: WaitingChannel(result: result))
    #expect(try channel.wait(0, events: Span()) == result)
  }

  @Test
  internal func buffered() throws(GDBRemoteError) {
    var channel = GDBPacketChannel(channel: WaitingChannel(result: .timeout))
    try channel.receive { message, _, _, _ in
      #expect(message == .acknowledge)
    }
    #expect(try channel.wait(0, events: Span()) == .channel)
    try channel.receive { message, _, _, _ in
      #expect(message == .acknowledge)
    }
    #expect(try channel.wait(0, events: Span()) == .timeout)
  }
}

private struct WaitingChannel: ByteChannel {
  fileprivate let result: WaitResult

  fileprivate func wait(_: Int32, events _: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    result
  }

  fileprivate func read(into buffer: inout OutputSpan<UInt8>)
      throws(TransportError) {
    buffer.append(UInt8(ascii: "+"))
    buffer.append(UInt8(ascii: "+"))
  }

  fileprivate func write(_ buffer: borrowing Span<UInt8>) throws(TransportError)
      -> Int {
    buffer.count
  }
}
