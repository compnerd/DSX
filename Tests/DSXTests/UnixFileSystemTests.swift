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
internal struct UnixFileSystemTests {
  @Test
  internal func completion() throws {
#if os(Android)
    let parent = "/data/local/tmp"
#else
    let parent = "/tmp"
#endif
    var template = Array("\(parent)/dsx-completion-XXXXXX".utf8CString)
    let path = try template.withUnsafeMutableBufferPointer { buffer in
      let base = try #require(buffer.baseAddress)
      return try String(cString: #require(mkdtemp(base)))
    }
    let directory = path + "/directory"
    let alias = path + "/alias"
    let dangling = path + "/dangling"
    let loop = path + "/loop"
    defer {
      _ = unlink(alias)
      _ = unlink(dangling)
      _ = unlink(loop)
      _ = rmdir(directory)
      _ = rmdir(path)
    }
    try #require(mkdir(directory, 0o700) == 0)
    try #require(DSX::symlink(directory, alias) == 0)
    try #require(DSX::symlink(path + "/missing", dangling) == 0)
    try #require(DSX::symlink(loop, loop) == 0)
    #expect(try UnixFileSystem.size(alias) == UnixFileSystem.size(directory))
    #expect(throws: Debuggee.Error.self) {
      _ = try UnixFileSystem.size(dangling)
    }
    let directories = try UnixFileSystem.complete(path + "/", directories: true)
    #expect(directories == [alias + "/", directory + "/"])
    let entries = try UnixFileSystem.complete(path + "/", directories: false)
    #expect(entries == [alias + "/", dangling, directory + "/", loop])
  }
}
#endif
