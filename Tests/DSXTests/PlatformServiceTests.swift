// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

#if os(anyAppleOS)
internal import Darwin

@Suite
internal struct PlatformServiceTests {
  @Test
  internal func process() throws {
    let identifier = ProcessIdentifier(rawValue: UInt64(getpid()))
    let processes = try ProcessIdentifier.snapshot()
    #expect(processes.contains(identifier))
    let info = try identifier.info
    #expect(info.process == identifier)
    #expect(info.name.isEmpty == false)
    #expect(info.arguments.isEmpty == false)
    #expect(info.architecture.isEmpty == false)
  }

  @Test
  internal func threads() throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let threads = try process.threads
    #expect(threads.isEmpty == false)
    #expect(try threads[0].alive)
  }

  @Test
  internal func files() throws {
    let path = "/private/tmp/dsx-native-\(getpid())"
    var files = FileSystem()
    let file =
        try files.open(path, options: [.create, .read, .truncate, .write],
                       mode: 0o600)
    let expected: Array<UInt8> = [0x44, 0x53, 0x53]
    #expect(try files.write(file, offset: 0,
                            bytes: expected.span) == expected.count)
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: expected.count) { output in
      try files.read(file, offset: 0, size: expected.count, into: &output)
    }
    #expect(bytes == expected)
    try files.close(file)
    let reused = try files.open(path, options: [.read, .write], mode: 0o600)
    #expect(reused == file)
    try files.close(reused)
    try NativeFileSystem.remove(path)
  }

  @Test
  internal func directory() throws {
    let root = "/private/tmp/dsx-directory-\(getpid())"
    let child = "\(root)/nested"
    defer {
      _ = rmdir(child)
      _ = rmdir(root)
    }
    try NativeFileSystem.create(child, mode: 0o700)
    var info = stat()
    let status = child.withCString { path in
      lstat(path, &info)
    }
    #expect(status == 0)
    #expect(info.st_mode & S_IFMT == S_IFDIR)
  }

  @Test
  internal func memory() throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    var control = NativeDebugControl()
    let address =
        try NativeMemory.allocate(process, size: 4096, readable: true,
                                  writable: true, executable: false,
                                  control: &control)
    let expected: Array<UInt8> = [0x44, 0x53, 0x53]
    var count = 0
    try NativeMemory.write(process, address: address, bytes: expected.span,
                           count: &count)
    #expect(count == expected.count)
    var bytes = Array<UInt8>()
    try bytes.append(addingCapacity: expected.count) { output in
      try NativeMemory.read(process, address: address, size: expected.count,
                            into: &output)
    }
    #expect(bytes == expected)
    let region = try NativeMemory.region(process, address: address)
    #expect(region.readable)
    #expect(region.writable)
    try NativeMemory.deallocate(process, address: address, size: 4096,
                                control: &control)
  }

  @Test
  internal func services() throws {
    var bytes = Array<UInt8>()
    var status: Debuggee.ProgramStatus?
    try bytes.append(addingCapacity: 64) { output in
      status = try Host.execute("printf DSX", directory: nil, timeout: 2,
                                into: &output)
    }
    #expect(status == .completed(.exited(0)))
    #expect(bytes == Array("DSX".utf8))
    #expect(try !Host.user(UInt64(getuid())).isEmpty)
    #expect(try !Host.group(UInt64(getgid())).isEmpty)
  }

  @Test
  internal func children() async throws {
    let configuration =
        Debuggee.Launch(executable: "/bin/sh", arguments: ["-c", "exit 0"])
    var session = PlatformSession()
    _ = try session.launch(configuration)
    for _ in 0 ..< 100 {
      session.reap()
      if session.servers.isEmpty {
        break
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    let empty = session.servers.isEmpty
    #expect(empty)
    try session.close()
  }

}
#endif
