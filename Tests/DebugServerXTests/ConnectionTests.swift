// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
internal import DSX
@testable internal import DebugServerX

@Suite
internal struct ConnectionTests {
  @Test
  internal func descriptor() throws {
    let connection = try Connection.parse("fd://7")
    guard case .descriptor(let descriptor) = connection else {
      Issue.record("expected a descriptor connection")
      return
    }
    #expect(descriptor == 7)
    #expect(throws: DSX.Error.self) {
      try Connection.parse("fd://-1")
    }
    #expect(throws: DSX.Error.self) {
      try Connection.parse("fd://2147483648")
    }
  }

  @Test
  internal func device() throws {
    let connection = try Connection.parse("device:///dev/ttyUSB0")
    guard case .device(let path) = connection else {
      Issue.record("expected a device connection")
      return
    }
    #expect(path == "/dev/ttyUSB0")

    let serial = try Connection.parse("serial:///dev/pts/1")
    guard case .device(let path) = serial else {
      Issue.record("expected a serial device connection")
      return
    }
    #expect(path == "/dev/pts/1")
  }

  @Test
  internal func pipe() throws {
    let connection = try Connection.parse("pipe://debug")
    guard case .pipe(let path) = connection else {
      Issue.record("expected a pipe connection")
      return
    }
    #expect(path == "debug")
  }

  @Test
  internal func unix() throws {
    let listening = try Connection.parse("unix:///tmp/dsx.sock")
    guard case .unix(let path, let reverse) = listening else {
      Issue.record("expected a Unix socket connection")
      return
    }
    #expect(path == "/tmp/dsx.sock")
    #expect(reverse == false)
    let connecting = try Connection.parse("unix:///tmp/dsx.sock", reverse: true)
    guard case .unix(let path, let reverse) = connecting else {
      Issue.record("expected a Unix socket connection")
      return
    }
    #expect(path == "/tmp/dsx.sock")
    #expect(reverse)
    #expect(throws: DSX.Error.self) {
      try Connection.parse("unix://")
    }
  }

  @Test
  internal func network() throws {
    let any = try Connection.parse(":1234")
    check(any, host: nil, port: 1234, reverse: false)
    let wildcard = try Connection.parse("*:1234")
    check(wildcard, host: nil, port: 1234, reverse: false)
    let ipv4 = try Connection.parse("127.0.0.1:1234")
    check(ipv4, host: "127.0.0.1", port: 1234, reverse: false)
    let ipv6 = try Connection.parse("[::1]:1234", reverse: true)
    check(ipv6, host: "::1", port: 1234, reverse: true)
    let maximum = try Connection.parse(":65535")
    check(maximum, host: nil, port: 65535, reverse: false)
  }

  @Test
  internal func invalid() {
    #expect(throws: DSX.Error.self) {
      try Connection.parse("::1:1234")
    }
    #expect(throws: DSX.Error.self) {
      try Connection.parse("[::1:1234")
    }
    #expect(throws: DSX.Error.self) {
      try Connection.parse("127.0.0.1:65536")
    }
    #expect(throws: DSX.Error.self) {
      try Connection.parse("127.0.0.1:")
    }
  }

  private func check(_ connection: Connection, host: String?, port: UInt16,
                     reverse: Bool) {
    guard case .network(let address, let service,
                        let direction) = connection else {
      Issue.record("expected a network connection")
      return
    }
    #expect(address == host)
    #expect(service == port)
    #expect(direction == reverse)
  }
}
