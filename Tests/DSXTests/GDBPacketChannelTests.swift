// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX
#if os(Windows)
internal import WinSDK
#elseif os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

@Suite
internal struct GDBPacketChannelTests {
  @Test
  internal func readiness() throws {
    let peer = try TestConnection()
    let channel = GDBPacketChannel(channel: peer.connect())
    #expect(try channel.wait(0, events: Span()) == .timeout)
    try peer.send([UInt8(ascii: "+")])
    #expect(try channel.wait(1000, events: Span()) == .channel)
  }

  @Test
  internal func event() throws {
    let peer = try TestConnection()
    let channel = GDBPacketChannel(channel: peer.connect())
#if os(Windows)
    let value = try #require(CreateEventW(nil, true, true, nil))
    let event = WaitHandle(value)
#else
    var descriptors: (CInt, CInt) = (-1, -1)
    let status = withUnsafeMutablePointer(to: &descriptors) { pointer in
      pointer.withMemoryRebound(to: CInt.self, capacity: 2) { pipe($0) }
    }
    #expect(status == 0)
    defer { _ = DSX::close(descriptors.1) }
    var byte: UInt8 = 1
    #expect(write(descriptors.1, &byte, 1) == 1)
    let event = WaitHandle(descriptors.0)
#endif
    defer { event.close() }
    let events = [event]
#if os(Windows)
    // Windows polls process events between bounded socket waits.
    #expect(try channel.wait(1000, events: events.span) == .timeout)
#else
    #expect(try channel.wait(1000, events: events.span) == .event)
#endif
  }

  @Test
  internal func buffered() throws {
    let peer = try TestConnection([UInt8(ascii: "+"), UInt8(ascii: "+")])
    var channel = GDBPacketChannel(channel: peer.connect())
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
