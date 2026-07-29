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
  private var allocated = true

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
    if allocated {
      memory.deinitialize(count: 16)
#if os(Windows)
      _ = VirtualFree(memory, 0, DSX::MEM_RELEASE)
#else
      _ = munmap(memory, size)
#endif
    }
  }

  fileprivate mutating func release() throws(Debuggee.Error) {
#if os(Windows)
    guard VirtualFree(memory, 0, DSX::MEM_RELEASE) else {
      throw .memory
    }
#else
    guard munmap(memory, size) == 0 else {
      throw .memory
    }
#endif
    allocated = false
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
  @Test
  internal func ownership() throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site()
    let original = fixture.bytes
    var table = BreakpointTable()
    var control = NativeDebugControl()
    let native = try table.install(fixture.process, site, native: true,
                                   control: &control)
    let client = try table.install(fixture.process, site, control: &control)
    #expect(native != client)
    let owned = table.native(native)
    #expect(owned)
    #expect(table.native(client) == false)
    #expect(table.find(fixture.process, site) == client)
    #expect(table.find(fixture.process, site, native: true) == native)
    let fault = Debuggee.Fault(address: site.address, domain: .windows)
    let stop =
        Debuggee.Stop(thread: fixture.thread, reason: .breakpoint, fault: fault)
    #expect(try table.hit(stop, control: control) == client)
    try table.remove(fixture.process, client, control: &control)
    #expect(table.find(fixture.process, site) == nil)
    #expect(fixture.bytes != original)
    #expect(try table.hit(stop, control: control) == native)
    try table.remove(fixture.process, native, control: &control)
    #expect(fixture.bytes == original)
  }

  @Test
  internal func maintenance() throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site()
    for stepping in [false, true] {
      var session = DebugSession()
      session.debuggee.observe(.started(fixture.thread))
      let identifier =
          try session.breakpoints.record(fixture.process, site, native: true)
      let stop = Debuggee.Stop(thread: fixture.thread, reason: .breakpoint,
                               breakpoint: identifier)
      session.deferred.append(.stopped(stop))
      if stepping {
        let action = Debuggee.Continuation(selection: .thread(fixture.thread),
                                           operation: .step)
        session.continuations.append(action)
      }
      guard case let .stopped(result) = try session.next(global: true) else {
        Issue.record("maintenance must preserve an explicit stop request")
        return
      }
      #expect(result.reason == (stepping ? .trace : .interrupt))
      #expect(result.breakpoint == identifier)
    }
  }

  @Test
  internal func packets() throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site()
    let original = fixture.bytes
    var session = DebugSession()
    session.debuggee.observe(.started(fixture.thread))
    var state = GDBRemoteSessionState(compatibility: .gdb)
    state.selection.general = .thread(fixture.thread)
    let address = String(site.address.rawValue, radix: 16)
    let payload = "0,\(address),\(site.size)"
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 16) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      for _ in 0 ..< 2 {
        try session.insert(payload.utf8Span.span, state: state, writer: &writer)
      }
      #expect(session.breakpoints.find(fixture.process, site) != nil)
      #expect(fixture.bytes != original)
      for _ in 0 ..< 2 {
        try session.remove(payload.utf8Span.span, state: state, writer: &writer)
        #expect(session.breakpoints.find(fixture.process, site) == nil)
        #expect(fixture.bytes == original)
      }
      let output = writer.finish()
      #expect(String(decoding: output.span, as: UTF8.self) == "OKOKOKOK")
    }
  }

#if os(Windows)
  @Test
  internal func detach() throws {
    let fixture = try BreakpointFixture()
    var session = DebugSession()
    session.state = .stopped(.attached)
    let info = Debuggee.Process.Info(process: fixture.process,
                                     parent: ProcessIdentifier(rawValue: 1),
                                     name: "fixture", architecture: "x86_64")
    session.debuggee.update(info)
    let site = fixture.site()
    _ = try session.breakpoints.install(fixture.process, site,
                                        control: &session.control)
    #expect(fixture.bytes[0] != 0x90)
    // Explicit detach retains client traps, even if native detach fails.
    #expect(throws: Debuggee.Error.self) {
      try session.detach(fixture.process, stopped: false)
    }
    #expect(fixture.bytes[0] != 0x90)
    #expect(session.breakpoints.find(fixture.process, site) == nil)
    #expect(session.debuggee.contains(fixture.process))
  }
#endif

  @Test(arguments: [false, true], [false, true])
  internal func relinquishment(shared: Bool, active: Bool) throws {
    let fixture = try BreakpointFixture()
    let original = fixture.bytes
    var table = BreakpointTable()
    var control = NativeDebugControl()
    let native = fixture.site()
    let client = fixture.site(shared ? 0 : 8)
    let identifier = try table.record(fixture.process, native, native: true)
    if active {
      try table.enable(identifier, control: &control)
    }
    _ = try table.install(fixture.process, client, control: &control)
    let armed = fixture.bytes
    try table.clear(fixture.process, preserving: true, control: &control)
    #expect(table.find(fixture.process, native, native: true) == nil)
    #expect(table.find(fixture.process, client) == nil)
    #expect(fixture.bytes[0 ..< 4] == (shared ? armed : original)[0 ..< 4])
    #expect(fixture.bytes[8 ..< 12] == armed[8 ..< 12])
  }

  @Test
  internal func slots() throws {
    for enabled in [false, true] {
      #expect(try DSX::slot(existing: 2, available: nil, enabled: enabled) == 2)
      #expect(try DSX::slot(existing: 2, available: 0, enabled: enabled) == 2)
    }
    #expect(try DSX::slot(existing: nil, available: 0, enabled: true) == 0)
    #expect(try DSX::slot(existing: nil, available: 0, enabled: false) == nil)
    #expect(try DSX::slot(existing: nil, available: nil, enabled: false) == nil)
    #expect(throws: Debuggee.Error.breakpoint) {
      try DSX::slot(existing: nil, available: nil, enabled: true)
    }
  }

  @Test
  internal func inheritance() throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site()
    var session = DebugSession()
    let identifier = try session.breakpoints.install(fixture.process, site,
                                                     control: &session.control)
    let child = ProcessIdentifier(rawValue: fixture.process.rawValue + 1)
    let thread =
        ProcessThreadIdentifier(process: child, thread: fixture.thread.thread)
    let fork =
        Debuggee.Fork(parent: fixture.thread, child: thread, vfork: false)
    session.complete(.forked(fork))
    #expect(session.breakpoints.find(child, site) != nil)
    #expect(session.breakpoints.find(fixture.process, site) == identifier)
    // The child identity is synthetic; no native operation is issued for it.
    session.breakpoints.forget(child)
    try session.breakpoints.remove(fixture.process, identifier,
                                   control: &session.control)
    #expect(fixture.bytes[0] == 0x90)
  }

  @Test
  internal func unmapped() throws {
    var fixture = try BreakpointFixture()
    let site = fixture.site()
    var session = DebugSession()
    let identifier = try session.breakpoints.install(fixture.process, site,
                                                     control: &session.control)
    try fixture.release()
    let region = try NativeMemory.region(fixture.process, address: site.address)
    #expect(region.mapped == false)
    try session.breakpoints.remove(fixture.process, identifier,
                                   control: &session.control)
    #expect(session.breakpoints.find(fixture.process, site) == nil)
  }

#if os(Android) || os(Linux)
  @Test
  internal func inaccessible() throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site()
    var session = DebugSession()
    let identifier = try session.breakpoints.install(fixture.process, site,
                                                     control: &session.control)
    #expect(mprotect(fixture.memory, fixture.size, PROT_NONE) == 0)
    defer { _ = mprotect(fixture.memory, fixture.size, PROT_READ | PROT_WRITE) }
    let region = try NativeMemory.region(fixture.process, address: site.address)
    #expect(region.mapped)
    #expect(throws: Debuggee.Error.self) {
      try session.breakpoints.remove(fixture.process, identifier,
                                     control: &session.control)
    }
    #expect(session.breakpoints.find(fixture.process, site) == identifier)
  }
#endif

  @Test(arguments: [true, false])
  internal func sharing(_ reverse: Bool) throws {
    let fixture = try BreakpointFixture()
    let original = fixture.bytes
    var session = DebugSession()
    let first = try session.breakpoints.install(fixture.process, fixture.site(),
                                                control: &session.control)
    let temporary = fixture.site(lifetime: .untilhit)
    let second = try session.breakpoints.install(fixture.process, temporary,
                                                 control: &session.control)
    let installed = fixture.bytes
    try session.breakpoints.remove(fixture.process, reverse ? second : first,
                                   control: &session.control)
    #expect(fixture.bytes == installed)
    try session.breakpoints.remove(fixture.process, reverse ? first : second,
                                   control: &session.control)
    #expect(fixture.bytes == original)
  }

  @Test
  internal func sharedhit() throws {
    let fixture = try BreakpointFixture()
    let original = fixture.bytes
    var session = DebugSession()
    let first = try session.breakpoints.install(fixture.process, fixture.site(),
                                                control: &session.control)
    let temporary = fixture.site(lifetime: .untilhit)
    let second = try session.breakpoints.install(fixture.process, temporary,
                                                 control: &session.control)
    let stop = Debuggee.Stop(thread: fixture.thread, reason: .breakpoint,
                             breakpoint: first)
    try session.breakpoints.complete(fixture.process, event: .stopped(stop),
                                     control: &session.control)
#if os(anyAppleOS) || os(Windows)
    #expect(fixture.bytes == original)
#endif
    #expect(session.breakpoints.site(second) == nil)
    try session.breakpoints.prepare(fixture.process, control: &session.control)
    #expect(fixture.bytes != original)
    try session.breakpoints.clear(fixture.process, control: &session.control)
    #expect(fixture.bytes == original)
  }

  @Test
  internal func legacy() throws {
    let fixture = try BreakpointFixture()
    var table = BreakpointTable()
    let site = ABI.breakpoint(fixture.site().address)
    let identifier = try table.record(fixture.process, site)
    #expect(table.find(fixture.process, ABI.breakpoint(site.address))
        == identifier)
  }

  @Test(arguments: [true, false])
  internal func writing(_ active: Bool) throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site(4)
    var session = DebugSession()
    let identifier = try session.breakpoints.install(fixture.process, site,
                                                     control: &session.control)
    if active == false {
      try session.breakpoints.disable(identifier, control: &session.control)
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
                                   control: &session.control)
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
    var control = NativeDebugControl()
    var table = BreakpointTable()
    let first = try table.install(process, site, control: &control)
    let patched = fixture.bytes
    #expect(patched != original)
    let second = try table.install(process, site, control: &control)
    #expect(first == second)
    #expect(table.site(first)?.advance == true)
    #expect(table.site(BreakpointIdentifier(rawValue: 0)) == nil)
    try table.remove(process, first, control: &control)
    #expect(table.site(second) == nil)
    #expect(fixture.bytes == original)
    #expect(throws: Debuggee.Error.breakpoint) {
      try table.remove(process, second, control: &control)
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
    let state = GDBRemoteSessionState(compatibility: .gdb)
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
      let size = Tuning.Packet.capacity
      try reply.append(addingCapacity: size) { output throws(GDBHandlerError) in
        var writer = GDBPacketWriter(output)
        let result: Result<GDBPacketDisposition, GDBHandlerError>
        do throws(GDBHandlerError) {
          let disposition =
              try session.breakpoints(bytes.span, state: state, writer: &writer)
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
  internal func preflight() throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site()
    let thread = Debuggee.Thread(identifier: fixture.thread)
    let child = Debuggee.Process(identifier: fixture.process, state: .stopped,
                                 threads: [thread])
    var session = DebugSession(debuggee: Debuggee(processes: [child]))
    let state = GDBRemoteSessionState(compatibility: .gdb)
    let address = String(site.address.rawValue, radix: 16)
    let width = String(site.size, radix: 16)
    let packet = "{\"breakpoint_requests\":[\"Z0,\(address),\(width)\"]}"
    let original = fixture.bytes
    let cases: Array<(String, Int, GDBHandlerError)> = [
      (packet + "garbage", 128, .malformed),
      (String(packet.dropLast()), 128, .malformed),
      (String(packet.dropLast(2)) + ",\"\n\"]}", 128, .malformed),
      (packet, 18, .capacity),
    ]
    for (packet, capacity, error) in cases {
      let bytes = Array(packet.utf8)
      withUnsafeTemporaryAllocation(of: UInt8.self,
                                    capacity: capacity) { buffer in
        var writer =
            GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
        #expect(throws: error) {
          try session.breakpoints(bytes.span, state: state, writer: &writer)
        }
      }
      #expect(session.breakpoints.find(fixture.process, site) == nil)
      #expect(fixture.bytes == original)
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
    var control = NativeDebugControl()
    var table = BreakpointTable()
    let identifier = try table.record(fixture.process, site)
    try table.prepare(fixture.process, control: &control)
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
    let traced = try table.classify(trace, control: control)
    #expect(traced.breakpoint == nil)
    #expect(traced.reason == .trace)
    let stop =
        Debuggee.Stop(thread: fixture.thread, reason: .breakpoint, fault: fault,
                      chance: .second)
    let classified = try table.classify(stop, control: control)
    #expect(classified.breakpoint == identifier)
    #expect(classified.chance == .second)
    try table.complete(fixture.process, event: .stopped(classified),
                       control: &control)
#if os(anyAppleOS) || os(Windows)
    #expect(fixture.bytes == original)
#endif
    try table.prepare(fixture.process, control: &control)
    try table.recover(fixture.process, control: &control)
    #expect(fixture.bytes == original)
    try table.prepare(fixture.process, control: &control)
    try table.clear(fixture.process, control: &control)
    #expect(table.site(identifier) == nil)
    #expect(fixture.bytes == original)
  }

  @Test(arguments: [BreakpointLifetime.permanent, .oneshot, .untilhit])
  internal func completion(_ lifetime: BreakpointLifetime) throws {
    let fixture = try BreakpointFixture()
    let process = fixture.process
    let original = fixture.bytes
    var control = NativeDebugControl()
    var table = BreakpointTable()
    let site = fixture.site(lifetime: lifetime)
    let identifier = try table.install(process, site, control: &control)
    let other = try table.install(process, fixture.site(8), control: &control)
    let interrupt = Debuggee.Stop(thread: fixture.thread, reason: .interrupt)
    try table.complete(process, event: .stopped(interrupt), control: &control)
    #expect((table.site(identifier) == nil) == (lifetime == .oneshot))
#if os(anyAppleOS) || os(Windows)
    #expect((fixture.memory[0] == original[0]) == (lifetime == .oneshot))
#endif
    let hit = Debuggee.Stop(thread: fixture.thread, reason: .breakpoint,
                            breakpoint: identifier)
    try table.complete(process, event: .stopped(hit), control: &control)
    #expect((table.site(identifier) == nil) == (lifetime != .permanent))
#if os(anyAppleOS) || os(Windows)
    #expect(fixture.memory[0] == original[0])
#endif
    #expect(fixture.memory[8] != original[8])
    #expect(table.site(other) != nil)
#if os(Android) || os(Linux)
    // Stop completion patches a traced thread with ptrace. This synthetic stop
    // names the test process itself, which cannot be its own ptrace tracer.
    for index in 0 ..< site.size {
      fixture.memory[index] = original[index]
    }
#endif
    try table.clear(process, control: &control)
    #expect(fixture.bytes == original)
  }

  @Test(arguments: [false, true])
  internal func inheritance(_ shared: Bool) throws {
    let fixture = try BreakpointFixture()
    let site = fixture.site()
    let original = fixture.bytes
    var control = NativeDebugControl()
    var table = BreakpointTable()
    let identifier = try table.install(fixture.process, site, control: &control)
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
    try table.clear(fixture.process, control: &control)
    #expect(fixture.bytes == original)
  }

  @Test(arguments: [false, true])
  internal func obsolete(_ executed: Bool) throws {
    let fixture = try BreakpointFixture()
    var control = NativeDebugControl()
    var table = BreakpointTable()
    let identifier =
        try table.install(fixture.process, fixture.site(), control: &control)
    let patched = fixture.bytes
    let event: Debuggee.Event = if executed {
      .executed(fixture.thread)
    } else {
      .exited(fixture.process, .exited(0))
    }
    try table.complete(fixture.process, event: event, control: &control)
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
    let identifier = try table.record(fixture.process, site, capacity: 1)
    #expect(try table.record(fixture.process, site, capacity: 1) == identifier)
    #expect(throws: Debuggee.Error.breakpoint) {
      try table.record(fixture.process, excess, capacity: 1)
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
      _ = try native.record(fixture.process, site)
    }
    let address =
        Debuggee.Address(rawValue: site.address.rawValue + UInt64(capacity))
    let full =
        BreakpointSite(address: address, size: 1, kind: .watchpoint(.readwrite))
    #expect(throws: Debuggee.Error.breakpoint) {
      try native.record(fixture.process, full)
    }
  }

  @Test
  internal func failure() throws {
    let fixture = try BreakpointFixture()
    let invalid = BreakpointSite(address: Debuggee.Address(rawValue: 0),
                                 size: fixture.site().size, kind: .software)
    var table = BreakpointTable()
    #expect(throws: Debuggee.Error.self) {
      try table.record(fixture.process, invalid)
    }
    #expect(table.find(fixture.process, invalid) == nil)
    let identifier = try table.record(fixture.process, fixture.site())
    #expect(identifier.rawValue == 1)
  }
}
#endif
