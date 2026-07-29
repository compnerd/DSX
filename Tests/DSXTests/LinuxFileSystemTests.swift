// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Linux)
internal import Glibc
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxFileSystemTests {
  @Test(.enabled(if: geteuid() == 0, "Requires chroot privilege"))
  internal func rooted() throws {
    var template = Array("/tmp/dsx-root-XXXXXX".utf8CString)
    let path = try template.withUnsafeMutableBufferPointer { buffer in
      try String(cString: #require(mkdtemp(buffer.baseAddress!)))
    }
    defer {
      for name in ["alias", "bridge", "payload", "sub/link"] {
        _ = unlink(path + "/" + name)
      }
      _ = rmdir(path + "/sub")
      _ = rmdir(path)
    }
    try #require(mkdir(path + "/sub", 0o700) == 0)
    let handle =
        try UnixFileSystem.open(path + "/payload", options: [.create, .write],
                                mode: 0o600)
    let bytes: Array<UInt8> = [1, 2, 3, 4]
    _ = try UnixFileSystem.write(handle, offset: 0, bytes: bytes.span)
    try UnixFileSystem.close(handle)
    try UnixFileSystem.link("/payload", at: path + "/alias")
    try UnixFileSystem.link("/sub", at: path + "/bridge")

    // Only async-signal-safe C operations execute in the fork child.
    let child = path.withCString { path in
      let child = DSX::fork()
      if child == 0 {
        if chroot(path) < 0 || chdir("/") < 0 {
          DSX::_exit(1)
        }
        _ = raise(SIGSTOP)
        DSX::_exit(0)
      }
      return child
    }
    try #require(child > 0)
    var reaped = false
    defer {
      if reaped == false {
        _ = DSX::kill(child, SIGKILL)
        _ = waitpid(child, nil, 0)
      }
    }
    var status: CInt = 0
    try #require(waitpid(child, &status, WUNTRACED) == child)
    try #require(UnixWaitStatus(status).stopped)
    var files = FileSystem()
    try files.select(ProcessIdentifier(rawValue: UInt64(child)))
    #expect(try files.size("/alias", directory: nil) == 4)
    #expect(try files.destination("/alias", directory: nil) == "/payload")
    let metadata = try files.status("/alias", directory: nil, link: true)
    #expect(metadata.mode & 0o170000 == 0o120000)
    let file = try files.open("../../alias", options: .read, mode: 0)
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 8) { raw in
      var output = OutputSpan(buffer: raw, initializedCount: 0)
      try files.read(file, offset: 0, size: 8, into: &output)
      #expect(output.count == 4 && output[3] == 4)
    }
    try files.close(file)
    try files.link("/payload", at: "/bridge/link", directory: nil)
    #expect(try files.size("/sub/link", directory: nil) == 4)
    try files.remove("/bridge/link", directory: nil)
    #expect(throws: Debuggee.Error.self) {
      _ = try files.status("/sub/link", directory: nil, link: true)
    }
    // The selected root is retained, not reopened through a reusable PID.
    try #require(DSX::kill(child, SIGKILL) == 0)
    try #require(waitpid(child, nil, 0) == child)
    reaped = true
    #expect(try files.size("/alias", directory: nil) == 4)
  }
}
#endif
