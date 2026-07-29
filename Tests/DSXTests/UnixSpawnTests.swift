// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(FreeBSD) || os(Linux) || os(OpenBSD)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import Testing
@testable internal import DSX

@Suite
internal struct UnixSpawnTests {
  @Test(arguments: [false, true])
  internal func arguments(_ fallback: Bool) throws {
    let script = #"test "$1" = '' && test "$2" = 'two words' && "# +
        #"test "$3" = '$(exit 42)' && test "$DSX_SPAWN_TEST" = 'λ'"#
    let environment = [Debuggee.Environment(name: "DSX_SPAWN_TEST", value: "λ"),
                       Debuggee.Environment(name: "PATH", value: "/missing")]
    // Search the parent's PATH, but pass the requested environment unchanged.
    let job = Debuggee.Launch(executable: "sh",
                              arguments: ["-c", script, "sh", "", "two words",
                                          "$(exit 42)"],
                              environment: environment, directory: "/")
    let child = try spawn(job, fallback: fallback)
    #expect(getpgid(child) == getpgrp())
    try wait(child)
  }

  @Test(arguments: [false, true])
  internal func directory(_ fallback: Bool) async throws {
    let parent = Host.directory
    try await withThrowingTaskGroup(of: Void.self) { tasks in
      for _ in 0 ..< 8 {
        tasks.addTask {
#if os(Android)
          let base = "/data/local/tmp"
#else
          let base = "/tmp"
#endif
          var template = Array("\(base)/dsx-spawn-XXXXXX".utf8CString)
          let path = try template.withUnsafeMutableBufferPointer { bytes in
            let pointer = try #require(bytes.baseAddress)
            return try String(cString: #require(mkdtemp(pointer)))
          }
          defer {
            _ = unlink(path + "/program")
            _ = unlink(path + "/output")
            _ = unlink(path + "/error")
            _ = rmdir(path)
          }
          try #require(DSX::symlink(Host.shell, path + "/program") == 0)
          let script = #"printf DSX; printf error >&2; test -f ./program"#
          let job = Debuggee.Launch(executable: "./program",
                                    arguments: ["-c", script], directory: path,
                                    input: "/dev/null", output: "output",
                                    error: "error")
          try wait(spawn(job, fallback: fallback))
          for (name, expected) in [("output", "DSX"), ("error", "error")] {
            let descriptor = DSX::open(path + "/" + name, O_RDONLY)
            try #require(descriptor >= 0)
            defer { _ = DSX::close(descriptor) }
            var bytes = InlineArray<8, UInt8>(repeating: 0)
            let count = withUnsafeMutableBytes(of: &bytes) {
              DSX::read(descriptor, $0.baseAddress, $0.count)
            }
            #expect(count == expected.utf8.count)
            for (index, byte) in expected.utf8.enumerated() {
              #expect(bytes[index] == byte)
            }
          }
        }
      }
      try await tasks.waitForAll()
    }
    #expect(Host.directory == parent)
  }

  @Test
  internal func failures() throws {
    let parent = Host.directory
    let jobs = [Debuggee.Launch(executable: Host.shell,
                               directory: "/dsx-missing-directory"),
                Debuggee.Launch(executable: "/dsx-missing-executable"),
                Debuggee.Launch(executable: "dsx-missing-executable"),
                Debuggee.Launch(executable: Host.shell,
                               input: "/dsx-missing-input")]
    for _ in 0 ..< 8 {
      for job in jobs {
        #expect(throws: Debuggee.Error.launch(ENOENT)) {
          _ = try spawn(job, fallback: true)
        }
      }
      #expect(throws: Debuggee.Error.launch(EACCES)) {
        _ = try spawn(Debuggee.Launch(executable: "/"), fallback: true)
      }
    }
    #expect(Host.directory == parent)
  }

  private func spawn(_ job: borrowing Debuggee.Launch, fallback: Bool)
      throws(Debuggee.Error) -> pid_t {
    if fallback {
      let descriptors = UnixDescriptors(reader: -1, writer: -1)
      return try job.spawn(descriptors: descriptors, tracing: false)
    }
    return try pid_t(Host.spawn(job).information.process.rawValue)
  }

  private func wait(_ child: pid_t) throws {
    var reaped = false
    defer {
      if reaped == false {
        _ = DSX::kill(child, SIGKILL)
        while waitpid(child, nil, 0) == -1 && errno == EINTR {
        }
      }
    }
    var status: CInt = 0
    for _ in 0 ..< 500 {
      let result = waitpid(child, &status, WNOHANG)
      if result == child {
        reaped = true
        #expect(status == 0)
        return
      }
      try #require(result == 0 || (result == -1 && errno == EINTR))
      _ = usleep(10_000)
    }
    Issue.record("child did not exit (possibly stopped by unintended tracing)")
  }
}
#endif
