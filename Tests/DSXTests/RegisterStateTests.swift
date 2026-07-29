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
        try GDBRegisterPacket.info(payload.span, registers: description,
                                   state: &state, writer: &writer)
      }
      #expect(throws: GDBHandlerError.self) {
        try GDBRegisterPacket.read(payload.span, number: (), session: session,
                                   state: state, writer: &writer)
      }
    }
  }

  @Test
  internal func failed() {
    let process = ProcessIdentifier(rawValue: UInt64.max)
    let thread = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 0))
    var session = DebugSession()
    session.snapshots.append(SavedRegisters(identifier: 1, thread: thread,
                                            bytes: []))
    #expect(throws: Debuggee.Error.self) {
      try session.restore(1, thread: nil)
    }
    #expect(session.snapshots.isEmpty)
  }

  @Test
  internal func terminated() {
    let process = ProcessIdentifier(rawValue: 1)
    let first = ProcessThreadIdentifier(process: process,
                                        thread: ThreadIdentifier(rawValue: 2))
    let second = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 3))
    var session = DebugSession()
    session.snapshots = [
      SavedRegisters(identifier: 1, thread: first, bytes: []),
      SavedRegisters(identifier: 2, thread: second, bytes: []),
    ]
    session.complete(.terminated(first, 0))
    #expect(session.snapshots.count == 1)
    #expect(session.snapshots.first?.thread == second)
  }

#if os(Windows)
  @Test
  internal func consumption() throws {
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
    #expect(session.snapshots.isEmpty)
    let second = try session.save(thread)
    #expect(second > first)
    #expect(throws: Debuggee.Error.self) {
      try session.restore(first, thread: nil)
    }
    try session.restore(second, thread: nil)
    #expect(session.snapshots.isEmpty)
  }
#endif
}
