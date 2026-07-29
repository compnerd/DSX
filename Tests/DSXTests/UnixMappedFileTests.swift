// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import Testing
@testable internal import DSX

@Suite
internal struct UnixMappedFileTests {
  @Test
  internal func truncation() throws {
    let directory = getenv("TMPDIR").map { String(cString: $0) } ?? "."
    var path = Array("\(directory)/dsx-mapping-XXXXXX".utf8CString)
    let handle = mkstemp(&path)
    try #require(handle >= 0)
    defer {
      _ = DSX::close(handle)
      _ = unlink(path)
    }
    let bytes = Array<UInt8>(repeating: 0x5a, count: Int(getpagesize()) * 3)
    var offset = 0
    while offset < bytes.count {
      let remaining = bytes.span.extracting(offset...)
      let count = try NativeFileSystem.write(handle, offset: UInt64(offset),
                                             bytes: remaining)
      try #require(count > 0)
      offset += count
    }
    let name = path.withUnsafeBytes {
      String(decoding: $0.dropLast(), as: UTF8.self)
    }
    let storage = try UnixMappedFile(name)
    try #require(ftruncate(handle, 0) == 0)
    let snapshot = storage.span()
    #expect(snapshot.count == bytes.count)
    for index in 0 ..< snapshot.count {
      #expect(snapshot[index] == bytes[index])
    }
  }
}
#endif
