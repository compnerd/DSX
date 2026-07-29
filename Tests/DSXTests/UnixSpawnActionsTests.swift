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
  @Test
  internal func descriptors() throws {
    var descriptors = try UnixSpawn.pipe()
    defer {
      _ = DSX::close(descriptors[0])
      _ = DSX::close(descriptors[1])
    }
    for index in 0 ..< descriptors.count {
      #expect(descriptors[index] > STDERR_FILENO)
      #expect(fcntl(descriptors[index], F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
    }

    let original = descriptors[0]
    let minimum = max(descriptors[0], descriptors[1]) + 2
    try UnixSpawn.isolate(&descriptors[0], minimum: minimum)
    #expect(descriptors[0] >= minimum)
    #expect(fcntl(descriptors[0], F_GETFD) & FD_CLOEXEC == FD_CLOEXEC)
    #expect(fcntl(original, F_GETFD) == -1)
  }

  @Test
  internal func defaults() throws(Debuggee.Error) {
    let job = Debuggee.Launch()
    try UnixSpawnActions.run(job) { _ in }
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
    let parent = Host.working
#if os(Android)
    let shell = "/system/bin/sh"
#else
    let shell = "/bin/sh"
#endif
    let job = Debuggee.Launch(executable: shell,
                              arguments: ["-c", #"test "$(pwd -P)" = /"#],
                              working: "/")
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
    #expect(Host.working == parent)
  }
}
#endif
