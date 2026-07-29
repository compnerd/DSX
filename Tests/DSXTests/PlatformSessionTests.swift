// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
internal import Testing
@testable internal import DSX
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

@Suite
internal struct PlatformSessionTests {
  @Test
  internal func handoff() throws {
    var servers = PlatformProcesses()
    var first = PlatformSession(tracking: servers.take())
    let configuration =
        Debuggee.Launch(executable: "/bin/sleep", arguments: ["10"])
    let child = try first.launch(configuration)
    try first.close()
    servers = first.release()
    let released = first.servers.isEmpty
    #expect(released)

    var second = PlatformSession(tracking: servers.take())
    let tracked = second.servers.last
    #expect(tracked?.process == child.process)
    #expect(tracked?.port == child.port)
    try second.remove(child.process)
    try second.close()
    servers = second.release()
  }

  @Test
  internal func zombie() async throws {
    var servers = PlatformProcesses()
    var session = PlatformSession(tracking: servers.take())
    let configuration = Debuggee.Launch(executable: "/usr/bin/true")
    _ = try session.launch(configuration)
    servers = session.release()

    for _ in 0 ..< 100 {
      servers.reap()
      var next = PlatformSession(tracking: servers.take())
      let empty = next.servers.isEmpty
      servers = next.release()
      if empty {
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("platform child was not reaped")
  }

  @Test
  internal func active() async throws {
    var session = PlatformSession()
    let configuration = Debuggee.Launch(executable: "/usr/bin/true")
    _ = try session.launch(configuration)

    for _ in 0 ..< 100 {
      session.reap()
      if session.servers.isEmpty {
        return
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("active platform child was not reaped")
  }

  @Test
  internal func event() async throws {
    var descriptors: InlineArray<2, CInt> = [-1, -1]
    let status = withUnsafeMutablePointer(to: &descriptors) { descriptors in
      descriptors.withMemoryRebound(to: CInt.self, capacity: 2) { values in
        pipe(values)
      }
    }
    #expect(status == 0)
    defer {
      _ = DSX::close(descriptors[0])
      _ = DSX::close(descriptors[1])
    }

    let command = "printf '1234\\n'"
    let arguments = ["-c", command]
    let child = try Host.launch("/bin/sh", arguments: arguments.span)
    var tracking = PlatformProcesses()
    _ = tracking.record(consume child)
    let stream = try Stream(.descriptor(descriptors[0]))
    let source = GDBPacketChannel(channel: ConnectionTransport.stream(stream))
    let result = try tracking.wait { _, events throws(GDBRemoteError) in
      try source.wait(1_000, events: events)
    }
    #expect(result == .event)

    var session = PlatformSession(tracking: consume tracking)
    for _ in 0 ..< 100 {
      session.reap()
      if session.servers.isEmpty {
        break
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    let empty = session.servers.isEmpty
    #expect(empty)
  }

  @Test
  internal func idle() throws {
    let descriptors = try UnixDescriptors()
    let stream = try Stream(.descriptor(descriptors.reader))
    var session = PlatformSession()
    let launch =
        Debuggee.Launch(executable: "/bin/sh", arguments: ["-c", "exit 0"])
    _ = try session.launch(launch)
    var remote = PlatformRemote(channel: ConnectionTransport.stream(stream),
                                session: consume session, compatibility: .lldb)
    defer {
      remote.close()
    }
    for _ in 0 ..< 100 {
      try remote.step()
      if remote.session.servers.isEmpty {
        return
      }
    }
    Issue.record("idle platform child was not reaped")
  }

  @Test
  internal func ownership() {
    var descriptors: InlineArray<2, CInt> = [-1, -1]
    let status = withUnsafeMutablePointer(to: &descriptors) { descriptors in
      descriptors.withMemoryRebound(to: CInt.self, capacity: 2) { values in
        pipe(values)
      }
    }
    #expect(status == 0)
    defer {
      _ = DSX::close(descriptors[1])
    }

    do {
      let monitor = WaitHandle(descriptors[0])
      let child =
          HostProcess(process: ProcessIdentifier(rawValue: 1), port: 0,
                      monitor: monitor)
      let identifier = child.information.process
      var tracking = PlatformProcesses()
      _ = tracking.record(consume child)
      let session = PlatformSession(tracking: consume tracking)
      let tracked = session.servers.last
      #expect(tracked?.process == identifier)
    }
    #expect(fcntl(descriptors[0], F_GETFD) == -1)
  }

  @Test
  internal func unregistered() throws {
    let descriptors = try UnixDescriptors()
    let reader = descriptors.release()
    let identifier = ProcessIdentifier(rawValue: 1)
    do {
      let child =
          HostProcess(process: identifier, port: 0, monitor: WaitHandle(reader))
      #expect(child.information.process == identifier)
    }
    #expect(fcntl(reader, F_GETFD) == -1)
  }
}
#endif
