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

private struct BreakpointFixture: ~Copyable {
  fileprivate let memory: UnsafeMutablePointer<UInt8>
  fileprivate let process: ProcessIdentifier
  fileprivate let size: Int

  fileprivate init() throws(Debuggee.Error) {
#if os(Windows)
    var information = SYSTEM_INFO()
    GetSystemInfo(&information)
    let size = Int(information.dwPageSize)
    let flags = DSX::MEM_RESERVE | DSX::MEM_COMMIT
    guard let mapping =
        VirtualAlloc(nil, SIZE_T(size), flags, DSX::PAGE_READWRITE) else {
      throw .memory
    }
#else
    let size = Int(getpagesize())
#if os(Android) || os(Linux)
    let flags = MAP_PRIVATE | MAP_ANONYMOUS
#else
    let flags = MAP_PRIVATE | MAP_ANON
#endif
    guard let mapping =
        mmap(nil, size, PROT_READ | PROT_WRITE, flags, -1, 0) else {
      throw .memory
    }
    if mapping == MAP_FAILED {
      throw .memory
    }
#endif
    memory = mapping.assumingMemoryBound(to: UInt8.self)
    self.size = size
    memory.initialize(repeating: 0x90, count: 16)
#if os(Windows)
    process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
#else
    process = ProcessIdentifier(rawValue: UInt64(getpid()))
#endif
  }

  deinit {
    memory.deinitialize(count: 16)
#if os(Windows)
    _ = VirtualFree(memory, 0, DSX::MEM_RELEASE)
#else
    _ = munmap(memory, size)
#endif
  }

  fileprivate func site(_ offset: Int = 0,
                        lifetime: BreakpointLifetime = .permanent)
      -> BreakpointSite {
#if arch(i386) || arch(x86_64)
    let size = 1
#else
    let size = 4
#endif
    let raw = UInt64(UInt(bitPattern: memory)) + UInt64(offset)
    return BreakpointSite(address: Debuggee.Address(rawValue: raw), size: size,
                          kind: .software, lifetime: lifetime)
  }

  fileprivate var thread: ProcessThreadIdentifier {
    let thread = ThreadIdentifier(rawValue: process.rawValue)
    return ProcessThreadIdentifier(process: process, thread: thread)
  }

  fileprivate var bytes: Array<UInt8> {
    Array(UnsafeBufferPointer(start: memory, count: 16))
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

@Suite(.serialized, .enabled(if: BreakpointFixture.available))
internal struct BreakpointTableTests {
  @Test(arguments: [true, false])
  internal func sharing(_ reverse: Bool) throws {
    let fixture = try BreakpointFixture()
    let original = fixture.bytes
    var session = DebugSession()
    let first = try session.breakpoints.insert(fixture.process, fixture.site(),
                                               context: &session.control)
    let temporary = fixture.site(lifetime: .untilhit)
    let second = try session.breakpoints.insert(fixture.process, temporary,
                                                context: &session.control)
    let installed = fixture.bytes
    try session.breakpoints.remove(fixture.process, reverse ? second : first,
                                   context: &session.control)
    #expect(fixture.bytes == installed)
    try session.breakpoints.remove(fixture.process, reverse ? first : second,
                                   context: &session.control)
    #expect(fixture.bytes == original)
  }

  @Test
  internal func sharedhit() throws {
    let fixture = try BreakpointFixture()
    let original = fixture.bytes
    var session = DebugSession()
    let first = try session.breakpoints.insert(fixture.process, fixture.site(),
                                               context: &session.control)
    let temporary = fixture.site(lifetime: .untilhit)
    let second = try session.breakpoints.insert(fixture.process, temporary,
                                                context: &session.control)
    let stop = Debuggee.Stop(thread: fixture.thread, reason: .breakpoint,
                             breakpoint: first)
    try session.breakpoints.complete(fixture.process, event: .stopped(stop),
                                     context: &session.control)
    #expect(fixture.bytes == original)
    #expect(session.breakpoints.site(second) == nil)
    try session.breakpoints.prepare(fixture.process, context: &session.control)
    #expect(fixture.bytes != original)
    try session.breakpoints.clear(fixture.process, context: &session.control)
    #expect(fixture.bytes == original)
  }

  @Test
  internal func legacy() throws {
    let fixture = try BreakpointFixture()
    var table = BreakpointTable()
    let site = ABI.breakpoint(fixture.site().address)
    let identifier = try table.insert(fixture.process, site)
    #expect(table.find(fixture.process, ABI.breakpoint(site.address))
        == identifier)
  }

  @Test(arguments: [true, false])
  internal func writing(_ active: Bool) throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site(4)
    var session = DebugSession()
    let identifier = try session.breakpoints.insert(fixture.process, site,
                                                    context: &session.control)
    if active == false {
      try session.breakpoints.disable(identifier, context: &session.control)
    }
    let patched = fixture.bytes
    let address = fixture.site(3).address
    let bytes: Array<UInt8> = [1, 2, 3, 4, 5, 6]
    let count =
        try session.write(fixture.process, address: address, bytes: bytes.span)
    #expect(count == bytes.count)
    var output = Array<UInt8>()
    try output.append(addingCapacity: bytes.count) { output in
      try session.read(fixture.process, address: address, size: bytes.count,
                       into: &output)
    }
    #expect(output == bytes)
    if active {
      for index in 4 ..< 4 + site.size {
        #expect(fixture.memory[index] == patched[index])
      }
    }
    let found = try session.search(fixture.process, address: address,
                                   length: UInt64(bytes.count),
                                   pattern: bytes.span)
    #expect(found == address)
    try session.breakpoints.remove(fixture.process, identifier,
                                   context: &session.control)
    for index in bytes.indices {
      #expect(fixture.memory[3 + index] == bytes[index])
    }
  }

  @Test
  internal func idempotence() throws {
    let fixture = try BreakpointFixture()
    let process = fixture.process
    let site = fixture.site()
    let original = fixture.bytes
    var context = NativeDebugControl()
    var table = BreakpointTable()
    let first = try table.insert(process, site, context: &context)
    let patched = fixture.bytes
    #expect(patched != original)
    let second = try table.insert(process, site, context: &context)
    #expect(first == second)
    let advance = table.advance(first)
    #expect(advance)
    #expect(table.advance(BreakpointIdentifier(rawValue: 0)) == false)
    try table.remove(process, first, context: &context)
    #expect(table.site(second) == nil)
    #expect(fixture.bytes == original)
    #expect(throws: Debuggee.Error.breakpoint) {
      try table.remove(process, second, context: &context)
    }
  }

  @Test
  internal func retransmission() throws {
    let fixture = try BreakpointFixture()
    let process = fixture.process
    let site = fixture.site()
    let thread = Debuggee.Thread(identifier: fixture.thread)
    let child = Debuggee.Process(identifier: process, state: .stopped,
                                 threads: [thread])
    let debuggee = Debuggee(processes: [child])
    var session = DebugSession(debuggee: debuggee)
    var state = GDBRemoteSessionState(compatibility: .gdb)
    let address = String(site.address.rawValue, radix: 16)
    let width = String(site.size, radix: 16)
    let packet =
        "{\"breakpoint_requests\":[\"Z0,\(address),\(width)\"," +
        "\"Z0,\(address),\(width)\",\"z0,\(address),\(width)\"," +
        "\"z0,\(address),\(width)\"]}"
    let bytes = Array(packet.utf8)
    let expected = Array("{\"results\":[\"OK\",\"OK\",\"OK\",\"OK\"]}".utf8)
    for _ in 0 ..< 2 {
      var reply = Array<UInt8>()
      let size = Configuration.PacketCapacity
      try reply.append(addingCapacity: size) { output throws(GDBHandlerError) in
        var writer = GDBPacketWriter(output)
        let result: Result<GDBPacketDisposition, GDBHandlerError>
        do throws(GDBHandlerError) {
          let disposition =
              try GDBMultiBreakpointPacket.handle(bytes.span, session: &session,
                                                  state: &state,
                                                  writer: &writer)
          result = .success(disposition)
        } catch {
          result = .failure(error)
        }
        output = writer.finish()
        _ = try result.get()
      }
      #expect(reply == expected)
      #expect(session.breakpoints.find(process, site) == nil)
    }
  }

  @Test
  internal func patching() throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site()
    let original = fixture.bytes
    var opcode = Array<UInt8>()
    try opcode.append(addingCapacity: site.size) { output in
      try ABI.breakpoint(site.size, into: &output)
    }
#if os(Windows) && arch(arm64)
    #expect(opcode == [0x00, 0x00, 0x3e, 0xd4])
#elseif arch(arm64)
    #expect(opcode == [0x00, 0x00, 0x20, 0xd4])
#endif
    var context = NativeDebugControl()
    var table = BreakpointTable()
    let identifier = try table.insert(fixture.process, site)
    try table.prepare(fixture.process, context: &context)
    #expect(Array(fixture.bytes.prefix(site.size)) == opcode)
    #expect(Array(fixture.bytes.dropFirst(site.size))
            == Array(original.dropFirst(site.size)))

    var restored = Array<UInt8>()
    try restored.append(addingCapacity: 16) { output in
      try NativeMemory.read(fixture.process, address: site.address, size: 16,
                            into: &output)
      table.restore(fixture.process, address: site.address, start: 0,
                    output: &output)
    }
    #expect(restored == original)

    let fault = Debuggee.Fault(address: site.address, domain: .posix)
    let trace =
        Debuggee.Stop(thread: fixture.thread, reason: .trace, fault: fault)
    let ignored = try table.classify(.stopped(trace), context: &context)
    guard case .stopped(let traced) = ignored else {
      Issue.record("expected a trace stop")
      return
    }
    #expect(traced.breakpoint == nil)
    #expect(traced.reason == .trace)
    let stop =
        Debuggee.Stop(thread: fixture.thread, reason: .breakpoint, fault: fault,
                      chance: .second)
    let event = try table.classify(.stopped(stop), context: &context)
    guard case .stopped(let classified) = event else {
      Issue.record("expected a breakpoint stop")
      return
    }
    #expect(classified.breakpoint == identifier)
    #expect(classified.chance == .second)
    try table.complete(fixture.process, event: event, context: &context)
    #expect(fixture.bytes == original)
    try table.prepare(fixture.process, context: &context)
    try table.recover(fixture.process, context: &context)
    #expect(fixture.bytes == original)
    try table.prepare(fixture.process, context: &context)
    try table.clear(fixture.process, context: &context)
    #expect(table.site(identifier) == nil)
    #expect(fixture.bytes == original)
  }

  @Test(arguments: [BreakpointLifetime.permanent, .oneshot, .untilhit])
  internal func completion(_ lifetime: BreakpointLifetime) throws {
    let fixture = try BreakpointFixture()
    let process = fixture.process
    let original = fixture.bytes
    var context = NativeDebugControl()
    var table = BreakpointTable()
    let site = fixture.site(lifetime: lifetime)
    let identifier = try table.insert(process, site, context: &context)
    let other = try table.insert(process, fixture.site(8), context: &context)
    let interrupt = Debuggee.Stop(thread: fixture.thread, reason: .interrupt)
    try table.complete(process, event: .stopped(interrupt), context: &context)
    #expect((table.site(identifier) == nil) == (lifetime == .oneshot))
    #expect((fixture.memory[0] == original[0]) == (lifetime == .oneshot))
    let hit = Debuggee.Stop(thread: fixture.thread, reason: .breakpoint,
                            breakpoint: identifier)
    try table.complete(process, event: .stopped(hit), context: &context)
    #expect((table.site(identifier) == nil) == (lifetime != .permanent))
    #expect(fixture.memory[0] == original[0])
    #expect(fixture.memory[8] != original[8])
    #expect(table.site(other) != nil)
    try table.clear(process, context: &context)
    #expect(fixture.bytes == original)
  }

  @Test(arguments: [false, true])
  internal func inheritance(_ shared: Bool) throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site()
    let original = fixture.bytes
    var context = NativeDebugControl()
    var table = BreakpointTable()
    let identifier = try table.insert(fixture.process, site, context: &context)
    let child = ProcessIdentifier(rawValue: fixture.process.rawValue + 1)
    let thread =
        ProcessThreadIdentifier(process: child,
                                thread: ThreadIdentifier(rawValue: 1))
    let fork =
        Debuggee.Fork(parent: fixture.thread, child: thread, vfork: shared)
    table.inherit(fork)
    let found = table.find(child, site)
    let inherited = try #require(found)
    #expect(inherited != identifier)
    #expect(table.site(inherited) == site)
    var restored = Array<UInt8>()
    try restored.append(addingCapacity: 16) { output in
      try NativeMemory.read(fixture.process, address: site.address, size: 16,
                            into: &output)
      table.restore(child, address: site.address, start: 0, output: &output)
    }
    #expect(restored == (shared ? fixture.bytes : original))
    table.forget(child)
    #expect(table.find(child, site) == nil)
    #expect(table.find(fixture.process, site) == identifier)
    try table.clear(fixture.process, context: &context)
    #expect(fixture.bytes == original)
  }

  @Test(arguments: [false, true])
  internal func obsolete(_ executed: Bool) throws {
    let fixture = try BreakpointFixture()
    var context = NativeDebugControl()
    var table = BreakpointTable()
    let identifier =
        try table.insert(fixture.process, fixture.site(), context: &context)
    let patched = fixture.bytes
    let event: Debuggee.Event = if executed {
      .executed(fixture.thread)
    } else {
      .exited(fixture.process, .exited(0))
    }
    try table.complete(fixture.process, event: event, context: &context)
    #expect(table.site(identifier) == nil)
    #expect(fixture.bytes == patched)
  }

  @Test
  internal func capacity() throws {
    guard HardwareBreakpoint.supports(.watchpoint(.readwrite)) else {
      return
    }
    let fixture = try BreakpointFixture()
    let site = BreakpointSite(address: fixture.site().address, size: 1,
                              kind: .watchpoint(.readwrite))
    let excess = BreakpointSite(address: fixture.site(8).address, size: 1,
                                kind: .watchpoint(.readwrite))
    var table = BreakpointTable()
    let identifier = try table.insert(fixture.process, site, capacity: 1)
    #expect(try table.insert(fixture.process, site, capacity: 1) == identifier)
    #expect(throws: Debuggee.Error.breakpoint) {
      try table.insert(fixture.process, excess, capacity: 1)
    }
    #expect(table.find(fixture.process, excess) == nil)
    guard let capacity = try HardwareBreakpoint.capacity else {
      return
    }
    var native = BreakpointTable()
    for index in 0 ..< capacity {
      let raw = site.address.rawValue + UInt64(index)
      let address = Debuggee.Address(rawValue: raw)
      let site = BreakpointSite(address: address, size: 1,
                                kind: .watchpoint(.readwrite))
      _ = try native.insert(fixture.process, site)
    }
    let address =
        Debuggee.Address(rawValue: site.address.rawValue + UInt64(capacity))
    let full =
        BreakpointSite(address: address, size: 1, kind: .watchpoint(.readwrite))
    #expect(throws: Debuggee.Error.breakpoint) {
      try native.insert(fixture.process, full)
    }
  }

  @Test
  internal func failure() throws {
    let fixture = try BreakpointFixture()
    let invalid = BreakpointSite(address: Debuggee.Address(rawValue: 0),
                                 size: fixture.site().size, kind: .software)
    var table = BreakpointTable()
    #expect(throws: Debuggee.Error.self) {
      try table.insert(fixture.process, invalid)
    }
    #expect(table.find(fixture.process, invalid) == nil)
    let identifier = try table.insert(fixture.process, fixture.site())
    #expect(identifier.rawValue == 1)
  }
}
#endif
