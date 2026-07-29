// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif !os(Windows)
internal import Glibc
#endif

@Suite
internal struct PlatformSessionTests {
  @Test(arguments: [GDBPacketLeaf.arguments, .run])
  internal func launch(_ packet: GDBPacketLeaf) throws {
    var session = PlatformSession()
    #if os(Windows)
    let shell = try WindowsEnvironment["COMSPEC"]
    let arguments = [shell, "/d", "/c",
                     "for /l %i in (1,1,2147483647) do @rem wait"]
    #else
    let arguments = [Host.shell, "-c", "sleep 30"]
    #endif
    let encoded = arguments.map { argument in
      argument.utf8.map {
        String($0 >> 4, radix: 16) + String($0 & 0x0f, radix: 16)
      }.joined()
    }
    let payload = packet == .run
        ? ";" + encoded.joined(separator: ";")
        : encoded.enumerated().map {
          "\($0.element.count),\($0.offset),\($0.element)"
        }.joined(separator: ",")
    let response = try exchange(packet, payload: payload, session: &session)
    #expect(response == "OK")
    let launched = session.process
    let process = try #require(launched)
    defer { try? session.remove(process) }
    #expect(process.rawValue > 1)
    #expect(try exchange(.qC, session: &session)
            == "QC\(String(process.rawValue, radix: 16))")
    #expect(try exchange(.qLaunchSuccess, session: &session) == "OK")
    let info = try exchange(.qProcessInfo, session: &session)
    #expect(info.contains("pid:\(String(process.rawValue, radix: 16));"))

    do {
      _ = try exchange(.run, payload: ";2f6473782d6d697373696e67",
                       session: &session)
      Issue.record("launch of a missing executable succeeded")
    } catch let error as GDBHandlerError {
      #expect(error != .unsupported)
    }
    #expect(session.process == nil)
    for packet in [GDBPacketLeaf.qC, .qProcessInfo, .qLaunchSuccess] {
      do {
        _ = try exchange(packet, session: &session)
        Issue.record("failed launch retained an unrelated process identity")
      } catch let error as GDBHandlerError {
        #expect(error == .code(GDBErrorCode.process))
      }
    }
  }

  @Test
  internal func missing() {
    var session = PlatformSession()
    do {
      _ = try session.spawn()
      Issue.record("launch without an executable succeeded")
    } catch {
      #expect(error == .process)
    }
    #expect(session.process == nil)
    let empty = session.servers.isEmpty
    #expect(empty)
  }

  private func exchange(_ packet: GDBPacketLeaf, payload: String = "",
                        session: inout PlatformSession) throws -> String {
    let bytes = Array(payload.utf8)
    var reply = Array<UInt8>()
    try reply.append(addingCapacity: 1024) { output throws(GDBHandlerError) in
      var writer = GDBPacketWriter(consume output)
      var failure: GDBHandlerError?
      do throws(GDBHandlerError) {
        _ = try session.handle(packet, payload: bytes.span, writer: &writer)
      } catch {
        failure = error
      }
      output = writer.finish()
      if let failure {
        throw failure
      }
    }
    return String(decoding: reply, as: UTF8.self)
  }

  #if !os(Windows)
  @Test(arguments: ["printf 'extra'; exec sleep 3",
                     "exec 1>&-; exec sleep 3", "sleep 1 & exit 0"])
  internal func monitoring(_ command: String) throws {
    let arguments = ["-c", "printf '1234\\n'; " + command]
    let child = try Host.launch(Host.shell, arguments: arguments.span)
    let process = child.information.process
    var tracking = PlatformProcesses()
    _ = tracking.record(consume child)
    defer { try? tracking.remove(process) }
    let descriptors = try UnixDescriptors()
    let stream = try Stream(.descriptor(descriptors.reader))
    let channel = GDBPacketChannel(channel: ConnectionTransport.stream(stream))
    for _ in 0 ..< 5 {
      let result = try tracking.wait { timeout, events throws(GDBRemoteError) in
        #expect(events.count == 0)
        return try channel.wait(timeout: timeout, events: events)
      }
      #expect(result == .timeout)
      tracking.reap()
      if tracking.isEmpty {
        return
      }
    }
    if command == "sleep 1 & exit 0" {
      Issue.record("descendant output delayed reaping its parent")
    }
  }

  @Test
  internal func handoff() throws {
    var servers = PlatformProcesses()
    var first = PlatformSession(tracking: servers.take())
    let configuration =
        Debuggee.Launch(executable: "/bin/sleep", arguments: ["10"])
    first.launch = configuration
    let child = try first.spawn()
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
    session.launch = configuration
    _ = try session.spawn()
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
    session.launch = configuration
    _ = try session.spawn()

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
    let result = try tracking.wait { timeout, events throws(GDBRemoteError) in
      #expect(events.count == 0)
      #expect(timeout == Int32(Configuration.Process.Interval))
      return try source.wait(timeout: timeout, events: events)
    }
    #expect(result == .timeout)

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
    session.launch = launch
    _ = try session.spawn()
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
  internal func ownership() throws {
    var descriptors: InlineArray<2, CInt> = [-1, -1]
    let status = withUnsafeMutablePointer(to: &descriptors) { descriptors in
      descriptors.withMemoryRebound(to: CInt.self, capacity: 2) { values in
        pipe(values)
      }
    }
    try #require(status == 0)
    defer {
      _ = DSX::close(descriptors[1])
    }

    var identity = stat()
    try #require(fstat(descriptors[0], &identity) == 0)
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
    closed(descriptors[0], identity: identity)
  }

  @Test
  internal func unregistered() throws {
    let descriptors = try UnixDescriptors()
    let writer = dup(descriptors.writer)
    try #require(writer >= 0)
    defer { _ = DSX::close(writer) }
    var identity = stat()
    try #require(fstat(descriptors.reader, &identity) == 0)
    let reader = descriptors.release()
    let identifier = ProcessIdentifier(rawValue: 1)
    do {
      let child =
          HostProcess(process: identifier, port: 0, monitor: WaitHandle(reader))
      #expect(child.information.process == identifier)
    }
    closed(reader, identity: identity)
  }

  private func closed(_ descriptor: CInt, identity: stat) {
    // Other tests may reuse the descriptor after its owner closes it. The
    // retained writer keeps the original pipe's identity alive for comparison.
    var current = stat()
    if fstat(descriptor, &current) == 0 {
      #expect(current.st_dev != identity.st_dev ||
              current.st_ino != identity.st_ino)
    } else {
      #expect(errno == EBADF)
    }
  }
  #endif
}
