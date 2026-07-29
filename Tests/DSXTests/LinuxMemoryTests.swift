// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Linux)
internal import Glibc
internal import Testing
@testable internal import DSX

@Suite(.serialized)
internal struct LinuxMemoryTests {
  @Test(arguments: [Debuggee.Continuation.Operation.resume, .step])
  internal func redirection(_ operation: Debuggee.Continuation.Operation)
      throws {
    let config = Debuggee.Launch(executable: "/bin/sleep", arguments: ["60"],
                                output: "/dev/null", error: "/dev/null")
    var session = DebugSession(launch: config)
    let process = try session.spawn()
    defer { try? session.close(cause: .normal) }
    guard case let .stopped(initial) = try session.settle() else {
      Issue.record("launch did not stop")
      return
    }
    let address = try session.allocate(process, size: 4096,
                                       permissions: [.read, .write, .execute])
    let site = ABI.breakpoint(address)
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: site.size * 2) { output in
      try ABI.breakpoint(site.size, into: &output)
      try ABI.breakpoint(site.size, into: &output)
    }
    _ = try session.write(process, address: address, bytes: bytes.span)
    _ = try session.breakpoints.install(process, site,
                                        control: &session.control)
    var registers =
        try NativeRegisterState(initial.thread, control: session.control)
    try registers.set(pc: address.rawValue)
    try registers.commit()
    let resume =
        Debuggee.Continuation(selection: .process(process), operation: .resume)
    let actions: InlineArray<1, Debuggee.Continuation> = [resume]
    try session.resume(actions.span, process: process)
    guard case let .stopped(first) =
        try session.next(global: true, blocking: true) else {
      Issue.record("software breakpoint did not stop")
      return
    }
    #expect(first.breakpoint != nil)
    let destination =
        Debuggee.Address(rawValue: address.rawValue + UInt64(site.size))
    _ = try session.breakpoints.install(process, ABI.breakpoint(destination),
                                        control: &session.control)
    var redirected =
        try NativeRegisterState(initial.thread, control: session.control)
    try redirected.set(pc: destination.rawValue)
    try redirected.commit()
    let redirect = Debuggee.Continuation(selection: .process(process),
                                         operation: operation)
    let requested: InlineArray<1, Debuggee.Continuation> = [redirect]
    // A PC write starts a new execution path. A hit there must not be consumed
    // as completion of an internal step over the preceding breakpoint.
    try session.resume(requested.span, process: process)
    guard case let .stopped(second) =
        try session.next(global: true, blocking: true) else {
      Issue.record("redirected execution did not stop")
      return
    }
    #expect(second.reason == .breakpoint)
    #expect(ABI.address(second) == destination)
  }

  @Test
  internal func region() throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let executable = try process.image
    let image = try #require(executable)
    let region = try NativeMemory.region(process, address: image.base)
    #expect(region.name == image.path)
    #expect(region.mapped)

    let size = Int(getpagesize())
    let memory = mmap(nil, size, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS, -1, 0)
    let allocation = try #require(memory)
    if allocation == MAP_FAILED {
      Issue.record("anonymous mapping failed")
      return
    }
    defer { _ = munmap(allocation, size) }
    let address =
        Debuggee.Address(rawValue: UInt64(UInt(bitPattern: allocation)))
    let anonymous = try NativeMemory.region(process, address: address)
    #expect(anonymous.name == nil)
    #expect(anonymous.mapped)
  }

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

  @Test(arguments: [false, true])
  internal func interruption(_ requested: Bool) throws {
    let config =
        Debuggee.Launch(executable: "/bin/sleep", arguments: ["60"],
                        output: "/dev/null", error: "/dev/null")
    var session = DebugSession(launch: config)
    let process = try session.spawn()
    let native = pid_t(process.rawValue)
    defer {
      _ = DSX::kill(native, SIGKILL)
      _ = waitpid(native, nil, 0)
    }
    try session.settle()

    if requested {
      session.control.requested = true
      try #require(DSX::tgkill(native, native, SIGSTOP) == 0)
    } else {
      // A different sender's stop is not one of our all-stop barriers.
      let sender = Glibc.fork()
      if sender == 0 {
        Glibc._exit(DSX::kill(native, SIGSTOP) == 0 ? 0 : 1)
      }
      try #require(sender > 0)
      var status: CInt = 0
      try #require(waitpid(sender, &status, 0) == sender)
      try #require(status == 0)
    }
    do {
      _ = try session.allocate(process, size: 4096,
                               permissions: [.read, .write])
      Issue.record("injected syscall swallowed a requested or external stop")
    } catch {
      #expect(error == .state)
    }
    let pending = session.control.status
    let status = try #require(pending)
    #expect(UnixWaitStatus(status).signal == SIGSTOP)
    #expect(session.control.thread == native)
  }

  @Test(arguments: [false, true])
  internal func allocation(_ interrupted: Bool) throws {
    let config =
        Debuggee.Launch(executable: "/bin/sleep", arguments: ["60"],
                        output: "/dev/null", error: "/dev/null")
    var session = DebugSession(launch: config)
    let process = try session.spawn()
    defer { _ = DSX::kill(pid_t(process.rawValue), SIGKILL) }
    try session.settle()

    for _ in 0 ..< 4 {
      if interrupted {
        // An all-stop request can lose to a breakpoint, leaving our SIGSTOP
        // pending until an injected syscall resumes the stopped thread.
        let native = pid_t(process.rawValue)
        try #require(DSX::tgkill(native, native, SIGSTOP) == 0)
      }
      let address =
          try session.allocate(process, size: 4096,
                               permissions: [.read, .write])
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
