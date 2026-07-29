// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
internal import Testing
@testable internal import DSX
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

@Suite
internal struct LinuxProcFSTests {
  @Test
  internal func process() throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let info = try process.info
    let argument = try #require(info.arguments.first)
    #expect(argument.isEmpty == false)
  }

  @Test
  internal func maps() throws {
    let source = "00400000-00452000 r-xp 00000000 08:02 1 /bin/test\n" +
                 "00651000-00652000 rw-s 00051000 08:02 1\n"
    let bytes = Array(source.utf8)
    var reader = LinuxMemoryMapReader(bytes.span)
    let first = reader.next()
    let text = try #require(first)
    #expect(text.start.rawValue == 0x00400000)
    #expect(text.end.rawValue == 0x00452000)
    #expect(text.offset == 0)
    #expect(reader.path(text) == "/bin/test")
    #expect(text.readable)
    #expect(text.writable == false)
    #expect(text.executable)
    #expect(text.shared == false)

    let second = reader.next()
    let data = try #require(second)
    #expect(data.start.rawValue == 0x00651000)
    #expect(data.end.rawValue == 0x00652000)
    #expect(data.offset == 0x00051000)
    #expect(data.path == nil)
    #expect(data.readable)
    #expect(data.writable)
    #expect(data.executable == false)
    #expect(data.shared)
    let end = reader.next()
    #expect(end == nil)
  }
}
#endif
