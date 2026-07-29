// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) || os(Linux) || os(Android) || os(anyAppleOS)
internal import Testing
@testable internal import DSX

#if os(Windows)
internal import WinSDK
#elseif os(Android)
internal import Android
#elseif os(Linux)
internal import Glibc
#else
internal import Darwin
#endif

private struct MemoryFixture: ~Copyable {
  private typealias Failure = GDBHandlerError

  fileprivate let memory: UnsafeMutablePointer<UInt8>
  fileprivate let process: ProcessIdentifier
  fileprivate let page: Int

  fileprivate init() throws {
#if os(Windows)
    var information = SYSTEM_INFO()
    GetSystemInfo(&information)
    page = Int(information.dwPageSize)
    let flags = DSX::MEM_RESERVE | DSX::MEM_COMMIT
    let raw = try #require(VirtualAlloc(nil, SIZE_T(page * 3), flags,
                                        DSX::PAGE_READWRITE))
    process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
#else
    page = Int(sysconf(Int32(_SC_PAGESIZE)))
    let mapping = mmap(nil, page * 3, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANON, -1, 0)
    #expect(mapping != MAP_FAILED)
    let raw = try #require(mapping == MAP_FAILED ? nil : mapping)
    process = ProcessIdentifier(rawValue: UInt64(getpid()))
#endif
    memory = raw.assumingMemoryBound(to: UInt8.self)
    memory.initialize(repeating: 0, count: page * 3)
    memory[0] = 0x12
    memory[1] = 0xab
  }

  deinit {
#if os(Windows)
    _ = VirtualFree(memory, 0, DSX::MEM_RELEASE)
#else
    _ = munmap(memory, page * 3)
#endif
  }

  fileprivate var address: UInt64 {
    UInt64(UInt(bitPattern: memory))
  }

  fileprivate func protect() throws {
#if os(Windows)
    var previous: DWORD = 0
    #expect(VirtualProtect(memory + page, SIZE_T(page), DSX::PAGE_NOACCESS,
                           &previous))
#else
    #expect(mprotect(memory + page, page, PROT_NONE) == 0)
#endif
  }

  fileprivate func response(_ packet: String) throws -> Array<UInt8> {
    let debuggee = Debuggee(processes: [
      Debuggee.Process(identifier: process, state: .stopped, threads: []),
    ])
    var session = DebugSession(debuggee: debuggee)
    var state = GDBRemoteSessionState(compatibility: .gdb, features: [.map])
    let bytes = Array(packet.utf8)
    let match = GDBPacketClassifier.classify(bytes.span)
    var result = Array<UInt8>()
    let capacity = Configuration.PacketCapacity
    try result.append(addingCapacity: capacity) { output throws(Failure) in
      var writer = GDBPacketWriter(output)
      let failure: GDBHandlerError?
      do throws(GDBHandlerError) {
        _ = try session.handle(match.leaf,
                               payload: bytes.span.extracting(match.payload...),
                               state: &state, writer: &writer)
        failure = nil
      } catch {
        failure = error
      }
      output = writer.finish()
      if let failure {
        throw failure
      }
    }
    return result
  }

  fileprivate static var available: Bool {
#if os(Linux)
    var vector = iovec()
    return DSX::process_vm_readv(getpid(), &vector, 0, &vector, 0, 0) == 0
#else
    true
#endif
  }
}

@Suite(.enabled(if: MemoryFixture.available))
internal struct MemoryPacketTests {
#if os(Windows) && (arch(i386) || arch(x86_64))
  @Test
  internal func partial() throws {
    let fixture = try MemoryFixture()
    let address =
        Debuggee.Address(rawValue: fixture.address + UInt64(fixture.page - 1))
    let site = BreakpointSite(address: address, size: 1, kind: .software)
    var session = DebugSession()
    let identifier = try session.breakpoints.insert(fixture.process, site,
                                                    context: &session.control)
    #expect(VirtualFree(fixture.memory + fixture.page, SIZE_T(fixture.page),
                        DWORD(MEM_DECOMMIT)))
    let bytes: Array<UInt8> = [0x12, 0x34]
    let written =
        try session.write(fixture.process, address: address, bytes: bytes.span)
    #expect(written == 1)
    #expect(fixture.memory[fixture.page - 1] == 0xcc)
    try session.breakpoints.remove(fixture.process, identifier,
                                   context: &session.control)
    #expect(fixture.memory[fixture.page - 1] == 0x12)
  }
#endif

  @Test
  internal func memory() throws {
    let fixture = try MemoryFixture()
    let address = String(fixture.address, radix: 16)
    let read = try fixture.response("m\(address),2")
    #expect(read == Array("12ab".utf8))
    let binary = try fixture.response("x\(address),2")
    #expect(binary == [0x12, 0xab])
    let write = try fixture.response("M\(address),2:34cd")
    #expect(write == Array("OK".utf8))
    let bytes = Array(UnsafeBufferPointer(start: fixture.memory, count: 2))
    #expect(bytes == [0x34, 0xcd])
    let upload = try fixture.response("X\(address),2:ab")
    #expect(upload == Array("OK".utf8))
    #expect(fixture.memory[0] == UInt8(ascii: "a"))
    #expect(fixture.memory[1] == UInt8(ascii: "b"))
  }

  @Test
  internal func ranges() throws {
    let fixture = try MemoryFixture()
    let address = String(fixture.address, radix: 16)
    let multiple =
        try fixture.response("MultiMemRead:ranges:\(address),2,\(address),1;")
    #expect(multiple == Array("2,1;".utf8) + [0x12, 0xab, 0x12])
    let trailing = try fixture.response("MultiMemRead:ranges:\(address),2,;")
    #expect(trailing == Array("2;".utf8) + [0x12, 0xab])
    try fixture.protect()
    let inaccessible = String(fixture.address + UInt64(fixture.page), radix: 16)
    let unreadable =
        try fixture.response("MultiMemRead:ranges:\(inaccessible),2;")
    #expect(unreadable == Array("0;".utf8))
  }

  @Test
  internal func search() throws {
    let fixture = try MemoryFixture()
    let address = String(fixture.address, radix: 16)
    let found = try fixture.response("qSearch:memory:\(address);2;\u{12}")
    #expect(found == Array("1,\(address)".utf8))
    let absent = try fixture.response("qSearch:memory:\(address);2;absent")
    #expect(absent == Array("0".utf8))
    let missing = try fixture.response("qSearch:memory:\(address);2;z")
    #expect(missing == Array("0".utf8))
  }

  @Test
  internal func holes() throws {
    let fixture = try MemoryFixture()
    let pattern = Array("needle".utf8)
    for index in 0 ..< 4 {
      fixture.memory[fixture.page - 4 + index] = pattern[index]
    }
    fixture.memory[fixture.page * 2] = pattern[4]
    fixture.memory[fixture.page * 2 + 1] = pattern[5]
    for index in pattern.indices {
      fixture.memory[fixture.page * 2 + 2 + index] = pattern[index]
    }
    try fixture.protect()
    let base = Debuggee.Address(rawValue: fixture.address)
    let session = DebugSession()
    let found = try session.search(fixture.process, address: base,
                                   length: UInt64(fixture.page * 3),
                                   pattern: pattern.span)
    let expected = fixture.address + UInt64(fixture.page * 2 + 2)
    #expect(found == Debuggee.Address(rawValue: expected))
  }

  @Test
  internal func map() throws {
    let fixture = try MemoryFixture()
    let reply = try fixture.response("qXfer:memory-map:read::0,1000")
    let xml = String(decoding: reply.dropFirst(), as: UTF8.self)
    #expect(xml.hasPrefix("<?xml version=\"1.0\"?>"))
    #expect(xml.contains("<memory-map>"))
    #expect(xml.contains("<memory type=\""))
  }

  @Test
  internal func region() throws {
    let fixture = try MemoryFixture()
    let address = String(fixture.address, radix: 16)
    let reply = try fixture.response("qMemoryRegionInfo:\(address)")
    let text = String(decoding: reply, as: UTF8.self)
    #expect(text.contains("permissions:rw;"))
    #expect(text.hasPrefix("start:"))
    #expect(text.contains(";size:"))
  }
}
#endif
