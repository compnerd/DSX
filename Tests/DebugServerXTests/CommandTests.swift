// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DebugServerX

@Suite
internal struct CommandTests {
  @Test
  internal func exclusive() {
    #expect(throws: (any Error).self) {
      try GDBServerCommand.parse(["--fd", "7", "--device", "/dev/ttyUSB0"])
    }
  }

  @Test
  internal func arguments() throws {
    let command =
        try GDBServerCommand.parse(["--fd", "7", "--", "/bin/echo", "value"])
    #expect(command.program().elementsEqual(["/bin/echo", "value"]))
    check(command.debuggee(), executable: "/bin/echo", arguments: ["value"])
  }

  @Test
  internal func network() throws {
    let command = try GDBServerCommand.parse([":0", "--", "/bin/echo", "value"])
    #expect(command.program().elementsEqual(["/bin/echo", "value"]))
    check(command.debuggee(), executable: "/bin/echo", arguments: ["value"])
  }

  @Test
  internal func attach() throws {
    let command = try GDBServerCommand.parse(["--fd", "7", "--attach", "123"])
    guard case .attach(let process)? = command.debuggee() else {
      Issue.record("expected an attached debuggee")
      return
    }
    #expect(process == "123")
  }

  @Test
  internal func debuggee() {
    #expect(throws: (any Error).self) {
      try GDBServerCommand.parse([
        "--fd", "7", "--attach", "123", "--", "/bin/echo",
      ])
    }
  }

  @Test
  internal func conflict() {
    #expect(throws: (any Error).self) {
      try GDBServerCommand.parse([
        "--pipe", "7", "--named-pipe", "port", ":0",
      ])
    }
  }

  @Test
  internal func listener() {
    #expect(throws: (any Error).self) {
      try GDBServerCommand.parse(["--fd", "7", "--pipe", "8"])
    }
  }

  private func check(_ debuggee: GDBServerDebuggee?, executable: String,
                     arguments: Array<String>) {
    guard case .launch(let program, let values)? = debuggee else {
      Issue.record("expected a launched debuggee")
      return
    }
    #expect(program == executable)
    #expect(values.elementsEqual(arguments))
  }

  @Test
  internal func notification() {
    #expect(throws: (any Error).self) {
      try GDBServerCommand.parse(["--pipe", "-1", ":0"])
    }
    #expect(throws: (any Error).self) {
      try GDBServerCommand.parse(["--named-pipe", "", ":0"])
    }
  }

  @Test
  internal func logging() throws {
    let debug = try PlatformServerCommand.parse(["--debug", "--listen", ":0"])
    let verbose =
        try PlatformServerCommand.parse(["--verbose", "--listen", ":0"])
    #expect(debug.selection() == "gdb-remote packets:debug")
    #expect(verbose.selection() == "all:trace")
  }

  @Test
  internal func platform() throws {
    let single = try PlatformServerCommand.parse(["--listen", ":0"])
    let multiple =
        try PlatformServerCommand.parse(["--server", "--listen", ":0"])
    #expect(single.server == false)
    #expect(multiple.server)
  }

  @Test
  internal func daemonize() throws {
    let gdb = try GDBServerCommand.parse(["--daemonize", "--fd", "7"])
    let platform =
        try PlatformServerCommand.parse(["--daemonize", "--listen", ":0"])
    #expect(gdb.daemonize)
    #expect(platform.daemonize)
  }

  @Test
  internal func registers() throws {
    let command = try GDBServerCommand.parse(["--native-regs", "--fd", "7"])
    #expect(command.registers)
  }

  @Test
  internal func attached() throws {
    let gdb = try GDBServerCommand.parse(["--fd=7", "--attach=123"])
    let platform = try PlatformServerCommand.parse(["-L:0"])
    #expect(gdb.fd == 7)
    #expect(gdb.attach == "123")
    #expect(platform.listen == ":0")
  }
}
