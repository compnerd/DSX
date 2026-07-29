// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxEventTests {
  @Test
  internal func ordering() throws {
    let pipe = try UnixDescriptors()
    try #require(fcntl(pipe.reader, F_SETFL, O_NONBLOCK) == 0)
    let events = try LinuxEventSource(.descriptor(pipe.reader))
    let payload = Array("qUnsupported".utf8)
    let checksum = String(payload.reduce(UInt8(0), &+), radix: 16)
    let peer = try TestConnection(Array("$qUnsupported#\(checksum)".utf8))
    var session = DebugSession()
    let process = ProcessIdentifier(rawValue: 7)
    session.deferred.append(.exited(process, .exited(0)))
    var remote = GDBRemote(channel: peer.connect(), session: session,
                           compatibility: .gdb)
    // Readable control input precedes a simultaneous native notification.
    // The event must still be published in the same turn.
    try remote.step(events: events)
    #expect(peer.output == Array("+$#00$W00#b7".utf8))
  }

  @Test
  internal func framing() throws {
    let pipe = try UnixDescriptors()
    try #require(fcntl(pipe.reader, F_SETFL, O_NONBLOCK) == 0)
    let events = try LinuxEventSource(.descriptor(pipe.reader))
    let payload = Array("qUnsupported".utf8)
    let checksum = String(payload.reduce(UInt8(0), &+), radix: 16)
    let packet = Array("$qUnsupported#\(checksum)".utf8)
    let peer = try TestConnection(Array(packet.prefix(3)))
    var session = DebugSession()
    let process = ProcessIdentifier(rawValue: 7)
    session.deferred.append(.exited(process, .exited(0)))
    var remote = GDBRemote(channel: peer.connect(), session: session,
                           compatibility: .gdb)
    // A queued event must not depend on another native notification.
    try remote.step(events: events)
    #expect(peer.output == Array("$W00#b7".utf8))
    try peer.send(Array(packet.dropFirst(3)))
    try remote.step(events: events)
    #expect(peer.output == Array("$W00#b7+$#00".utf8))
  }

  @Test
  internal func notification() throws {
    let pipe = try UnixDescriptors()
    try #require(fcntl(pipe.reader, F_SETFL, O_NONBLOCK) == 0)
    let events = try LinuxEventSource(.descriptor(pipe.reader))
    let peer = try TestConnection()
    let channel = GDBPacketChannel(channel: peer.connect())
    let control = LinuxDebugControl()
    for _ in 0 ..< 2 {
      var bytes = InlineArray<256, UInt8> { _ in 1 }
      let count = withUnsafeBytes(of: &bytes) {
        write(pipe.writer, $0.baseAddress, $0.count)
      }
      #expect(count == 256)
      let ready =
          try events.wait(control) { delay, fds throws(GDBRemoteError) in
            #expect(delay == nil)
            let flags = fcntl(fds[0].descriptor, F_GETFD)
            #expect(flags & FD_CLOEXEC == FD_CLOEXEC)
            return try channel.wait(timeout: .zero, events: fds)
          }
      #expect(ready == .event)
      try events.drain()
      let drained = try events.wait(control) { _, fds throws(GDBRemoteError) in
        try channel.wait(timeout: .zero, events: fds)
      }
      #expect(drained == .timeout)
    }
  }

  @Test
  internal func validation() throws {
    let pipe = try UnixDescriptors()
    do {
      _ = try LinuxEventSource(.descriptor(pipe.reader))
      Issue.record("blocking notification descriptor accepted")
    } catch {
      #expect(error == .system(EINVAL))
    }
    try #require(fcntl(pipe.writer, F_SETFL, O_NONBLOCK) == 0)
    do {
      _ = try LinuxEventSource(.descriptor(pipe.writer))
      Issue.record("write-only notification descriptor accepted")
    } catch {
      #expect(error == .system(EINVAL))
    }
  }

  @Test
  internal func ownership() throws {
    var pipe = try UnixDescriptors()
    try #require(fcntl(pipe.reader, F_SETFL, O_NONBLOCK) == 0)
    do {
      let events = try LinuxEventSource(.descriptor(pipe.reader))
      try #require(DSX::close(pipe.writer) == 0)
      pipe.writer = -1
      do {
        try events.drain()
        Issue.record("closed notification source accepted")
      } catch {
        #expect(error == .system(EPIPE))
      }
    }
    #expect(fcntl(pipe.reader, F_GETFD) >= 0)
  }

  @Test
  internal func output() throws {
    var pipe = try UnixDescriptors()
    try #require(fcntl(pipe.reader, F_SETFL, O_NONBLOCK) == 0)
    var control = LinuxDebugControl()
    control.reader = pipe.reader
    #expect(try Debuggee.Output(pipe.reader, closed: &control.exhausted) == nil)
    #expect(control.exhausted == false)
    try #require(DSX::close(pipe.writer) == 0)
    pipe.writer = -1
    #expect(try Debuggee.Output(pipe.reader, closed: &control.exhausted) == nil)
    #expect(control.exhausted == true)
    let events = LinuxEventSource()
    _ = events.wait(control) { delay, fds in
      #expect(delay == Tuning.Debuggee.polling)
      #expect(fds[1].descriptor == -1)
      return .timeout
    }
  }

  @Test(arguments: [false, true], [false, true])
  internal func outputPrecedesCompletion(_ exiting: Bool, _ queued: Bool)
      throws {
    var pipe = try UnixDescriptors()
    try #require(fcntl(pipe.reader, F_SETFL, O_NONBLOCK) == 0)
    let capacity = Tuning.Output.capacity
    let bytes = Array(repeating: UInt8(ascii: "x"), count: capacity * 2 + 1)
    let count = bytes.withUnsafeBytes { bytes in
      write(pipe.writer, bytes.baseAddress, bytes.count)
    }
    try #require(count == bytes.count)
    let process = ProcessIdentifier(rawValue: 7)
    let thread = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 7))
    let stop = Debuggee.Stop(thread: thread, reason: .breakpoint)
    var control = LinuxDebugControl()
    control.process = process
    control.reader = pipe.reader
    pipe.reader = -1
    defer { control.reset() }
    let completion: Debuggee.Event =
        exiting ? .exited(process, .exited(0)) : .stopped(stop)
    if queued {
      control.events.append(completion)
    } else {
      control.deferred = completion
    }
    var captured = Array<UInt8>()
    while captured.count < bytes.count {
      guard case let .output(identifier) = try control.event() else {
        Issue.record("completion overtook buffered output")
        return
      }
      #expect(identifier == process)
      try captured.append(addingCapacity: capacity) { output in
        try control.output(identifier, into: &output)
      }
      #expect(control.deferred != nil)
    }
    #expect(captured == bytes)
    let event = try control.event()
    if exiting {
      guard case let .exited(identifier, .exited(0)) = event else {
        Issue.record("exit did not follow output")
        return
      }
      #expect(identifier == process)
      #expect(control.process == nil)
    } else {
      guard case let .stopped(result) = event else {
        Issue.record("stop did not follow output")
        return
      }
      #expect(result.thread == thread)
    }
    #expect(control.deferred == nil)
  }

  @Test
  internal func outputFailureRetainsStop() throws {
    let process = ProcessIdentifier(rawValue: 7)
    let thread = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 7))
    let stop = Debuggee.Stop(thread: thread, reason: .breakpoint)
    var control = LinuxDebugControl()
    control.process = process
    control.reader = -1
    control.deferred = .stopped(stop)
    #expect(throws: Debuggee.Error.system(EBADF)) {
      try control.event()
    }
    #expect(control.deferred != nil)
    guard case let .stopped(result) = try control.event(output: false) else {
      Issue.record("suppressed output prevented stop delivery")
      return
    }
    #expect(result.thread == thread)
    #expect(control.deferred == nil)
  }

  @Test(arguments: [false, true])
  internal func mask(_ blocked: Bool) throws {
    var signals = sigset_t()
    sigemptyset(&signals)
    sigaddset(&signals, SIGCHLD)
    var previous = sigset_t()
    let operation = blocked ? SIG_BLOCK : SIG_UNBLOCK
    try #require(pthread_sigmask(operation, &signals, &previous) == 0)
    defer { _ = pthread_sigmask(SIG_SETMASK, &previous, nil) }
    do {
      let events = try LinuxEventSource(.signals)
      var control = LinuxDebugControl()
      events.configure(&control)
      #expect(control.unblock == (blocked == false))
      var current = sigset_t()
      #expect(pthread_sigmask(SIG_BLOCK, nil, &current) == 0)
      #expect(sigismember(&current, SIGCHLD) == 1)
      // Thread-directed delivery avoids another test worker consuming it.
      try #require(pthread_kill(pthread_self(), SIGCHLD) == 0)
      let peer = try TestConnection()
      let channel = GDBPacketChannel(channel: peer.connect())
      let ready = try events.wait(control) { _, fds throws(GDBRemoteError) in
        try channel.wait(timeout: .zero, events: fds)
      }
      #expect(ready == .event)
      try events.drain()
    }
    var restored = sigset_t()
    #expect(pthread_sigmask(SIG_BLOCK, nil, &restored) == 0)
    #expect(sigismember(&restored, SIGCHLD) == (blocked ? 1 : 0))
  }
}
#endif
