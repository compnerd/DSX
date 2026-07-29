// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Linux)
internal import Glibc
internal import Testing
@testable internal import DSX

@Suite(.serialized)
internal struct LinuxMemoryTests {
  @Test
  internal func teardown() throws {
    let config =
        Debuggee.Launch(executable: "/bin/sh",
                        arguments: ["-c", "printf output"])
    var session = DebugSession(launch: config)
    let process = try session.spawn()
    let identifier = pid_t(process.rawValue)
    defer {
      _ = DSX::kill(identifier, SIGKILL)
      _ = waitpid(identifier, nil, 0)
    }
    try session.settle()

    let action =
        Debuggee.Continuation(selection: .process(process), operation: .resume)
    let actions: InlineArray<1, Debuggee.Continuation> = [action]
    try session.resume(actions.span, process: process)
    let event = try session.next(global: true, blocking: true)
    guard case .output = event else {
      Issue.record("debuggee output was not captured")
      return
    }

    try session.close(cause: .normal)
    let active = session.active
    #expect(active == false)
  }

  @Test
  internal func cleanup() throws {
    let config =
        Debuggee.Launch(executable: "/bin/sleep", arguments: ["60"],
                        output: "/dev/null", error: "/dev/null")
    var session = DebugSession(launch: config)
    let process = try session.spawn()
    let identifier = pid_t(process.rawValue)
    defer {
      _ = DSX::kill(identifier, SIGKILL)
      _ = waitpid(identifier, nil, 0)
    }
    try session.settle()

    try session.close(cause: .normal)

    #expect(DSX::kill(identifier, 0) == -1)
    #expect(errno == ESRCH)
  }

  @Test
  internal func allocation() throws {
    let config =
        Debuggee.Launch(executable: "/bin/sleep", arguments: ["60"],
                        output: "/dev/null", error: "/dev/null")
    var session = DebugSession(launch: config)
    let process = try session.spawn()
    defer { _ = DSX::kill(pid_t(process.rawValue), SIGKILL) }
    try session.settle()

    for _ in 0 ..< 4 {
      let address =
          try session.allocate(process, size: 4096, readable: true,
                               writable: true, executable: false)
      let expected: Array<UInt8> = [0x44, 0x53, 0x53]
      var count = 0
      try NativeMemory.write(process, address: address, bytes: expected.span,
                             count: &count)
      #expect(count == expected.count)
      var actual = Array<UInt8>()
      try actual.append(addingCapacity: expected.count) { output in
        try NativeMemory.read(process, address: address, size: expected.count,
                              into: &output)
      }
      #expect(actual == expected)
      try session.deallocate(process, address: address)
    }

    try session.terminate(process)
    try session.settle()
    try session.close(cause: .normal)
  }
}
#endif
