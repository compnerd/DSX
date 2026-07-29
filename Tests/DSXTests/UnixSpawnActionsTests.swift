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
internal struct UnixSpawnActionsTests {
  @Test(arguments: ["/", "/tmp", "/./"])
  internal func shell(_ directory: String) throws(Debuggee.Error) {
    let parent = Host.directory
    var output = Array<UInt8>()
    var status: Debuggee.ProgramStatus?
    try output.append(addingCapacity: 64) { output throws(Debuggee.Error) in
      status = try Host.execute("printf DSX", directory: directory, timeout: 2,
                                into: &output)
    }
    #expect(status == .completed(.exited(0)))
    #expect(output == Array("DSX".utf8))
    #expect(Host.directory == parent)
  }

  @Test
  internal func descriptors() throws {
    var descriptors = try UnixDescriptors()
    for descriptor in [descriptors.reader, descriptors.writer] {
      #expect(descriptor > STDERR_FILENO)
      #expect(fcntl(descriptor, F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
    }

    let original = descriptors.reader
    var identity = stat()
    try #require(fstat(original, &identity) == 0)
    let minimum = max(descriptors.reader, descriptors.writer) + 2
    try descriptors.isolate(minimum: minimum)
    #expect(descriptors.reader >= minimum)
    #expect(fcntl(descriptors.reader, F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
    var current = stat()
    if fstat(original, &current) == 0 {
      let device = current.st_dev != identity.st_dev
      let inode = current.st_ino != identity.st_ino
      #expect(device || inode)
    } else {
      #expect(errno == EBADF)
    }
  }

  @Test
  internal func defaults() throws(Debuggee.Error) {
    let job = Debuggee.Launch()
    var actions = try UnixSpawnActions()
    try actions.configure(job)
  }

  @Test
  internal func inheritance() throws {
    let descriptor =
        try NativeFileSystem.open("/dev/null", options: [.read], mode: 0)
    defer {
      _ = DSX::close(descriptor)
    }
    #expect(fcntl(descriptor, F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
  }

  @Test
  internal func directory() throws {
    let parent = Host.directory
    let job = Debuggee.Launch(executable: Host.shell,
                              arguments: ["-c", #"test "$(pwd -P)" = /"#],
                              directory: "/")
    let process: ProcessIdentifier
    do throws(Debuggee.Error) {
      let child = try Host.spawn(job)
      process = child.information.process
    } catch {
#if os(Android) || os(OpenBSD) || os(FreeBSD)
      // Older Android and FreeBSD SDKs, and OpenBSD, lack this action.
      if case .unsupported = error {
        return
      }
#endif
      throw error
    }
    var status: CInt = 0
    let identifier = pid_t(process.rawValue)
    while true {
      let waited = waitpid(identifier, &status, 0)
      if waited == identifier {
        break
      }
      try #require(waited == -1 && errno == EINTR)
    }
    #expect(status == 0)
    #expect(Host.directory == parent)
  }
}
#endif
