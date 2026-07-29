// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

#if os(Windows)
internal import WinSDK
#endif

@Suite
internal struct RegisterStateTests {
  @Test(arguments: ["80000000", "8000000000000000", "ffffffffffffffff"])
  internal func bounds(_ number: String) throws {
    let process = ProcessIdentifier(rawValue: 1)
    let thread = ThreadIdentifier(rawValue: 2)
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    var session = DebugSession()
    let threads = [Debuggee.Thread(identifier: identifier)]
    session.debuggee.insert(Debuggee.Process(identifier: process,
                                             threads: threads))
    var state = GDBRemoteSessionState(compatibility: .lldb)
    state.selection.general = .thread(identifier)
    let payload = Array(number.utf8)
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 256) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      #expect(throws: GDBHandlerError.self) {
        let description = RegisterDescription()
        try description.info(payload.span, state: state, writer: &writer)
      }
      #expect(throws: GDBHandlerError.self) {
        try session.read(register: payload.span, state: state, writer: &writer)
      }
    }
  }

  @Test
  internal func stale() {
    let thread =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    var session = DebugSession()
    let selection = GDBRemoteSelection(stopped: thread)
    let state =
        GDBRemoteSessionState(compatibility: .lldb, selection: selection)
    let payload = Array<UInt8>()
    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 256) { buffer in
      var writer =
          GDBPacketWriter(OutputSpan(buffer: buffer, initializedCount: 0))
      #expect(throws: GDBHandlerError.debuggee(.thread)) {
        try session.save(payload.span, state: state, writer: &writer)
      }
    }
  }

  @Test
  internal func failed() throws {
    let process = ProcessIdentifier(rawValue: UInt64.max)
    let thread = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 0))
    var session = DebugSession()
    let identifier =
        try session.snapshots.record(SavedRegisters(thread: thread, bytes: []))
    #expect(throws: Debuggee.Error.self) {
      try session.restore(identifier, thread: nil)
    }
    #expect(session.snapshots.isEmpty == true)
  }

  @Test
  internal func terminated() throws {
    let process = ProcessIdentifier(rawValue: 1)
    let first = ProcessThreadIdentifier(process: process,
                                        thread: ThreadIdentifier(rawValue: 2))
    let second = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 3))
    let other = ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 2),
                                        thread: first.thread)
    var session = DebugSession()
    let unrelated =
        try session.snapshots.record(SavedRegisters(thread: other, bytes: []))
    let removed =
        try session.snapshots.record(SavedRegisters(thread: first, bytes: []))
    let retained =
        try session.snapshots.record(SavedRegisters(thread: second, bytes: []))
    session.complete(.terminated(first, 0))
    #expect(throws: Debuggee.Error.register) {
      try session.snapshots.take(removed)
    }
    #expect(try session.snapshots.take(retained).thread == second)
    session.snapshots.discard(process)
    #expect(try session.snapshots.take(unrelated).thread == other)
    #expect(session.snapshots.isEmpty == true)
  }

  @Test
  internal func consumption() throws {
    let thread =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    var snapshots = RegisterSnapshots()
    let first = try snapshots.record(SavedRegisters(thread: thread, bytes: [1]))
    let second =
        try snapshots.record(SavedRegisters(thread: thread, bytes: [2]))
    let third = try snapshots.record(SavedRegisters(thread: thread, bytes: [3]))
    #expect(try snapshots.take(second).bytes == [2])
    #expect(throws: Debuggee.Error.register) { try snapshots.take(second) }
    #expect(try snapshots.take(first).bytes == [1])
    #expect(try snapshots.take(third).bytes == [3])
    #expect(snapshots.isEmpty == true)
  }

  @Test
  internal func identifiers() throws {
    let process = ProcessIdentifier(rawValue: 1)
    let thread = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 2))
    var snapshots = RegisterSnapshots()
    let first = try snapshots.record(SavedRegisters(thread: thread, bytes: []))
    snapshots.clear()
    let second = try snapshots.record(SavedRegisters(thread: thread, bytes: []))
    #expect(second > first)
    #expect(throws: Debuggee.Error.register) { try snapshots.take(first) }
    snapshots.discard(process)
    #expect(throws: Debuggee.Error.register) { try snapshots.take(second) }
    #expect(snapshots.isEmpty == true)
  }

#if os(Windows)
  @Test
  internal func redirection() throws {
    var identifier: DWORD = 0
    let handle = try #require(CreateThread(nil, 0, { _ in 0 }, nil,
                                           DWORD(WinSDK.CREATE_SUSPENDED),
                                           &identifier))
    defer {
      _ = ResumeThread(handle)
      _ = WaitForSingleObject(handle, WinSDK.INFINITE)
      _ = CloseHandle(handle)
    }
    let original = try CONTEXT(handle, flags: DSX::CONTEXT_ALL)
    defer { try? original.commit(to: handle) }
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let selected = ThreadIdentifier(rawValue: UInt64(identifier))
    let thread = ProcessThreadIdentifier(process: process, thread: selected)
    let saved = try NativeRegisterState(thread)
    var registers = try NativeRegisterState(thread)
    let address = try saved.pc ^ 0x10
    try registers.set(pc: address)
    #expect(try registers.pc == address)
    #expect(try NativeRegisterState(thread).pc == saved.pc)

    let description = RegisterDescription(registers.configuration)
    for index in 0 ..< description.count {
      let record = try #require(description.register(index))
      if case .program = record.role {
        continue
      }
      let size = record.bytes * 2
      try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size * 2,
                                        { buffer in
        let first = UnsafeMutableBufferPointer(rebasing: buffer[..<size])
        let second = UnsafeMutableBufferPointer(rebasing: buffer[size...])
        var before =
            GDBPacketWriter(OutputSpan(buffer: first, initializedCount: 0))
        var after =
            GDBPacketWriter(OutputSpan(buffer: second, initializedCount: 0))
        try before.emit(saved, register: record, model: description)
        try after.emit(registers, register: record, model: description)
        try #require(before.finish().count == size)
        try #require(after.finish().count == size)
        #expect(first.elementsEqual(second))
      })
    }
    try registers.commit()
    #expect(try NativeRegisterState(thread).pc == address)
  }

  @Test
  internal func restoration() throws {
    var identifier: DWORD = 0
    let handle = try #require(CreateThread(nil, 0, { _ in 0 }, nil,
                                           DWORD(WinSDK.CREATE_SUSPENDED),
                                           &identifier))
    defer {
      _ = ResumeThread(handle)
      _ = WaitForSingleObject(handle, WinSDK.INFINITE)
      _ = CloseHandle(handle)
    }
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let selected = ThreadIdentifier(rawValue: UInt64(identifier))
    let thread = ProcessThreadIdentifier(process: process, thread: selected)
    var session = DebugSession()
    let first = try session.save(thread)
    try session.restore(first, thread: nil)
    #expect(session.snapshots.isEmpty == true)
    let second = try session.save(thread)
    #expect(second > first)
    #expect(throws: Debuggee.Error.self) {
      try session.restore(first, thread: nil)
    }
    try session.restore(second, thread: nil)
    #expect(session.snapshots.isEmpty == true)
  }
#endif
}
