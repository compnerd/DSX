// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX
#if os(Android)
internal import Android
#elseif os(Linux)
internal import Glibc
#endif

@Suite
internal struct LinuxProcFSTests {
  @Test
  internal func lifetime() throws {
    let bytes = Array("1-2 r-xp 0 00:00 0 /tmp/image\n".utf8)
    let result = path(bytes.span)
    guard let result else {
      Issue.record("missing borrowed pathname")
      return
    }
    #expect(String(decoding: result, as: UTF8.self) == "/tmp/image")
    var reader = LinuxMemoryMapReader(bytes.span)
    let first = reader.next()
    let map = try #require(first)
    let retained = reader.path(map)
    let end = reader.next()
    #expect(end == nil)
    guard let retained else {
      Issue.record("missing retained pathname")
      return
    }
    #expect(String(decoding: retained, as: UTF8.self) == "/tmp/image")
  }

  @_lifetime(copy bytes)
  private func path(_ bytes: consuming Span<UInt8>) -> Span<UInt8>? {
    var reader = LinuxMemoryMapReader(bytes)
    guard let map = reader.next() else {
      return nil
    }
    return reader.path(map)
  }

  @Test
  internal func comparison() {
    let names = ["", "/tmp/image", "/tmp/other", "/tmp/é", "/tmp/e\u{301}",
                 "/tmp/路径", "/tmp/😀", "/tmp/�", "/tmp/��",
                 String(repeating: "long", count: 128)]
    var paths = names.map { Array($0.utf8) }
    let suffixes: Array<Array<UInt8>> =
        [[0xff], [0xc0, 0xaf], [0xe2, 0x82], [0, 0xff]]
    for suffix in suffixes {
      paths.append(Array("/tmp/".utf8) + suffix)
    }
    for path in paths {
      let decoded = String(decoding: path, as: UTF8.self)
      for name in names {
        #expect(name.matches(utf8: path.span) == (name == decoded))
      }
    }
  }

#if os(Android) || os(Linux)
  @Test
  internal func process() throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let info = try process.info
    let argument = try #require(info.arguments.first)
    #expect(argument.isEmpty == false)
  }

#if os(Linux)
  @Test
  internal func libraries() throws {
    // Use a stopped tracee so kernels without process_vm_readv can exercise
    // the ptrace fallback. Reading the untraced test process cannot do that.
    let child = DSX::fork()
    if child == 0 {
      guard DSX::ptrace(DSX::PTRACE_TRACEME, 0, nil, nil) == 0 else {
        DSX::_exit(1)
      }
      _ = raise(SIGSTOP)
      DSX::_exit(0)
    }
    try #require(child > 0)
    defer {
      _ = DSX::kill(child, SIGKILL)
      _ = waitpid(child, nil, 0)
    }
    var status: CInt = 0
    try #require(waitpid(child, &status, 0) == child)
    try #require(UnixWaitStatus(status).stopped)
    let process = ProcessIdentifier(rawValue: UInt64(child))
    var libraries = try LinuxLibraryCursor(process)
    let first = try libraries.next()
    let executable = try #require(first)
    // glibc's first entry has an empty l_name, not a missing executable.
    #expect(executable.path.isEmpty)
    #expect(executable.link.rawValue > 0)
    #expect(executable.dynamic.rawValue > 0)
    let region =
        try NativeMemory.region(process, address: executable.dynamic)
    let image = try process.image
    #expect(region.name == image?.path)
    let location = try process.address
    let width = ABI.width.bytes
    let size = width * 2
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size) { bytes in
      var output = OutputSpan(buffer: bytes, initializedCount: 0)
      try NativeMemory.read(process, address: location, size: width,
                            into: &output)
      let pointer = try output.span.integer(at: 0, count: width,
                                            little: ABI.endian == .little)
      output.removeLast(output.count)
      // The packet exposes a pointer slot. Dereference it before reading
      // r_debug, whose first two fields are r_version and r_map.
      let address = Debuggee.Address(rawValue: pointer)
      try NativeMemory.read(process, address: address, size: width * 2,
                            into: &output)
      let version = try output.span.integer(at: 0, count: 4,
                                            little: ABI.endian == .little)
      let link = try output.span.integer(at: width, count: width,
                                         little: ABI.endian == .little)
      #expect(version >= 1)
      #expect(link == executable.link.rawValue)
    }
  }
#endif

  @Test
  internal func instances() throws {
    let page = getpagesize()
    let path = "/tmp/dsx-images-\(getpid())"
    let options: FileOptions = [.create, .exclusive, .read, .write]
    let file = try NativeFileSystem.open(path, options: options, mode: 0o600)
    defer {
      try? NativeFileSystem.close(file)
      try? NativeFileSystem.remove(path)
    }
    var bytes = Array<UInt8>(repeating: 0, count: Int(page) * 3)
    bytes.replaceSubrange(0 ..< 6, with: [0x7f, 0x45, 0x4c, 0x46, 2, 1])
    bytes[32] = 64
    bytes[54] = 56
    bytes[56] = 1
    bytes[64] = 1
    let size = UInt64(bytes.count)
    for index in 0 ..< 8 {
      bytes[104 + index] = UInt8(truncatingIfNeeded: size >> (index * 8))
    }
    #expect(try NativeFileSystem.write(file, offset: 0,
                                       bytes: bytes.span) == bytes.count)
    let first = mmap(nil, bytes.count, PROT_READ, MAP_PRIVATE, file, 0)
    try #require(first != MAP_FAILED)
    defer { _ = munmap(first, bytes.count) }
    let second = mmap(nil, bytes.count, PROT_READ, MAP_PRIVATE, file, 0)
    try #require(second != MAP_FAILED)
    defer { _ = munmap(second, bytes.count) }
    let base = try #require(first)
    let status = mprotect(base + Int(page), Int(page), PROT_READ | PROT_WRITE)
    #expect(status == 0)
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let images = try process.images(.name).filter { $0.path == path }
    try #require(images.count == 2)
    #expect(images[0].base != images[1].base)
  }
#endif

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
    guard let path = reader.path(text) else {
      Issue.record("missing pathname")
      return
    }
    #expect(String(decoding: path, as: UTF8.self) == "/bin/test")
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

  @Test
  internal func recovery() throws {
    let source = "garbage\n0-\n0-1 r\n10000000000000000-1 r-xp 0 00:00 0\n" +
                 "A-F rw-p a 00:00 0 /a path (deleted)"
    let bytes = Array(source.utf8)
    var reader = LinuxMemoryMapReader(bytes.span)
    let value = reader.next()
    let map = try #require(value)
    #expect(map.start.rawValue == 10)
    #expect(map.end.rawValue == 15)
    #expect(map.offset == 10)
    let absolute = reader.absolute(map)
    #expect(absolute)
    guard let path = reader.path(map) else {
      Issue.record("missing pathname")
      return
    }
    #expect(String(decoding: path, as: UTF8.self) == "/a path (deleted)")
    let end = reader.next()
    #expect(end == nil)
  }
}
