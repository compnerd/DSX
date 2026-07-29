// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

#if os(Windows)
internal import WinSDK
#elseif os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

@Suite
internal struct NativeMemoryTests {
#if os(Windows)
  @Test
  internal func allocations() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let foreign = ProcessIdentifier(rawValue: UInt64.max)
    let unrelated = MemoryAllocation(process: foreign,
                                     address: Debuggee.Address(rawValue: 1),
                                     size: 1)
    var session = DebugSession()
    defer { try? session.deallocate(process) }
    for _ in 0 ..< 3 {
      session.allocations.append(unrelated)
      _ = try session.allocate(process, size: 4096, readable: true,
                               writable: true, executable: false)
    }
    try session.deallocate(process)
    #expect(session.allocations.count == 3)
    #expect(session.allocations.allSatisfy { $0.process == foreign })
  }

  @Test
  internal func release() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    var session = DebugSession()
    defer { try? session.deallocate(process) }
    let address = try session.allocate(process, size: 4096, readable: true,
                                       writable: true, executable: false)
    let invalid = Debuggee.Address(rawValue: 0)
    session.allocations.append(MemoryAllocation(process: process,
                                                address: invalid, size: 4096))
    #expect(throws: Debuggee.Error.self) {
      try session.deallocate(process)
    }
    #expect(session.allocations.count == 2)
    #expect(session.allocations.first?.address == address)
    session.allocations.removeLast()
  }
#endif

  @Test(arguments: [0, 1, 2, 257], [0, 32, 32768])
  internal func frames(_ count: Int, _ capacity: Int) throws {
#if os(Android) || os(Linux)
    let size = max(1, count) * 2 * MemoryLayout<UInt>.size
    let config =
        Debuggee.Launch(executable: Host.shell, arguments: ["-c", "sleep 60"],
                        output: "/dev/null", error: "/dev/null")
    var session = DebugSession(launch: config)
    let process = try session.spawn()
    defer { try? session.close(cause: .normal) }
    try session.settle()
    let address =
        try session.allocate(process, size: UInt64(size), readable: true,
                             writable: true, executable: false)
#else
    let session = DebugSession()
#if os(Windows)
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
#else
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
#endif
#endif
    var frames = Array<UInt>(repeating: 0, count: max(1, count) * 2)
    try frames.withUnsafeMutableBufferPointer { frames in
#if os(Android) || os(Linux)
      let base = UInt(address.rawValue)
#else
      let base = UInt(bitPattern: frames.baseAddress)
#endif
      for index in 0 ..< count {
        // The final frame points backward to exercise cycle rejection.
        frames[index * 2] = if index + 1 < count {
          base + UInt((index + 1) * 2 * MemoryLayout<UInt>.size)
        } else {
          base
        }
      }
#if os(Android) || os(Linux)
      let bytes = UnsafeRawBufferPointer(frames).bindMemory(to: UInt8.self)
      var written = 0
      try NativeMemory.write(process, address: address, bytes: bytes.span,
                             count: &written)
      #expect(written == size)
#endif
      try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                        { buffer in
        var output = OutputSpan(buffer: buffer, initializedCount: 0)
        if count > 0, capacity > 32 {
          let address = Debuggee.Address(rawValue: UInt64(base))
          try session.read(process, address: address,
                           size: MemoryLayout<UInt>.size * 2, into: &output)
          #expect(output.count == MemoryLayout<UInt>.size * 2)
          output.removeAll()
        }
        var writer = GDBPacketWriter(consume output)
        try writer.emit(memory: process, frame: count > 0 ? UInt64(base) : 0,
                        session: session)
        let result = String(decoding: writer.output.span, as: UTF8.self)
        let entries = result.utf8.filter { $0 == UInt8(ascii: "{") }.count
        let expected =
            capacity > 32 ? min(count, Configuration.Stack.Frames) : 0
        #expect(entries == expected)
        #expect(entries == 0 ? result.isEmpty : result.hasSuffix("}],"))
      })
    }
  }

  @Test(arguments: [0, 1, UInt64.max - 7, UInt64.max])
  internal func frames(_ address: UInt64) throws {
    let session = DebugSession()
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 128) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      try writer.emit(memory: ProcessIdentifier(rawValue: UInt64.max),
                      frame: address, session: session)
      #expect(writer.count == 0)
    }
  }

  @Test(arguments: [0, 1])
  internal func empty(_ size: Int) throws {
#if os(Windows)
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
#else
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
#endif
    var byte: UInt8 = 0
    try withUnsafePointer(to: &byte) { pointer in
      let address =
          Debuggee.Address(rawValue: UInt64(UInt(bitPattern: pointer)))
      let buffer = UnsafeMutableBufferPointer<UInt8>(start: nil, count: 0)
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      try NativeMemory.read(process, address: address, size: size,
                            into: &output)
      #expect(output.count == 0)
      #expect(throws: Debuggee.Error.memory) {
        try NativeMemory.read(process, address: address, size: -1,
                              into: &output)
      }
      #expect(throws: Debuggee.Error.self) {
        try NativeMemory.read(ProcessIdentifier(rawValue: UInt64.max),
                              address: address, size: size, into: &output)
      }
    }
  }
}
