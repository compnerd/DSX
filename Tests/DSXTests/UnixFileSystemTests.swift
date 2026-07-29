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
  internal func libraries() throws {
#if os(Android)
    let parent = "/data/local/tmp"
#else
    let parent = "/tmp"
#endif
    var template = Array("\(parent)/dsx-libraries-XXXXXX".utf8CString)
    let path = try template.withUnsafeMutableBufferPointer { buffer in
      let base = try #require(buffer.baseAddress)
      return try String(cString: #require(mkdtemp(base)))
    }
    let first = path + "/first"
    let second = path + "/second"
    defer {
      _ = unlink(first + "/libfixture.so")
      _ = unlink(second + "/libfixture.so")
      _ = unlink(path + "/libfixture.so")
      _ = unlink(path + "/loop")
      _ = rmdir(first)
      _ = rmdir(second)
      _ = rmdir(path)
    }
    try #require(mkdir(first, 0o700) == 0)
    try #require(mkdir(second, 0o700) == 0)
    for directory in [first, second] {
      let handle =
          try UnixFileSystem.open(directory + "/libfixture.so",
                                  options: [.create, .write], mode: 0o600)
      try UnixFileSystem.close(handle)
    }
    let ordered = try UnixFileSystem.library("libfixture.so", directory: path,
                                             paths: ":missing:first::second:")
    #expect(ordered == first + "/libfixture.so")
    let reversed = try UnixFileSystem.library("libfixture.so", directory: path,
                                              paths: "second:first")
    #expect(reversed == second + "/libfixture.so")
    let relative = try UnixFileSystem.library("./libfixture.so",
                                              directory: path, paths: "first")
    #expect(relative == path + "/./libfixture.so")
    let absolute = try UnixFileSystem.library(path + "/absent/libfixture.so",
                                              directory: path, paths: first)
    #expect(absolute == path + "/absent/libfixture.so")
    let missing = try UnixFileSystem.library("absent.so", directory: path,
                                             paths: "first:second")
    #expect(missing == path + "/absent.so")
    try #require(DSX::symlink(path + "/loop", path + "/loop") == 0)
    #expect(throws: Debuggee.Error.system(ELOOP)) {
      _ = try UnixFileSystem.library("libfixture.so", directory: path,
                                     paths: "loop:first")
    }
    let handle =
        try UnixFileSystem.open(path + "/libfixture.so",
                                options: [.create, .write], mode: 0o600)
    try UnixFileSystem.close(handle)
    let local = try UnixFileSystem.library("libfixture.so", directory: path,
                                           paths: "first:second")
    #expect(local == path + "/libfixture.so")
  }

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
