// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsPlatformProcessTests {
  @Test
  internal func ownership() throws {
    let shell = try WindowsEnvironment["COMSPEC"]
    let config =
        Debuggee.Launch(executable: shell, arguments: ["/d", "/c", "exit 0"])
    let child = try Host.spawn(config)
    let identifier = child.information.process
    var processes = PlatformProcesses()
    _ = processes.record(consume child)
    var handle: HANDLE?
    _ = try processes.wait { timeout, events throws(Debuggee.Error) in
      #expect(timeout == -1)
      guard events.count == 1 else {
        throw .state
      }
      handle = events[0].value
      #expect(UInt64(GetProcessId(handle)) == identifier.rawValue)
      #expect(WaitForSingleObject(handle, 5_000) == WinSDK.WAIT_OBJECT_0)
      return .event
    }
    var transferred = processes.take()
    let empty = processes.isEmpty
    #expect(empty)
    #expect(UInt64(GetProcessId(handle)) == identifier.rawValue)
    let current = GetCurrentProcess()
    var duplicate: HANDLE?
    try #require(DuplicateHandle(current, handle, current, &duplicate, 0, false,
                                 DWORD(DUPLICATE_SAME_ACCESS)))
    let reference = try #require(duplicate)
    defer { _ = CloseHandle(reference) }
    transferred.reap()
    let reaped = transferred.isEmpty
    #expect(reaped)
    // Another test can reuse a closed handle value for a different object.
    #expect(CompareObjectHandles(handle, reference) == false)
  }

  @Test
  internal func termination() throws {
    let shell = try WindowsEnvironment["COMSPEC"]
    let config = Debuggee.Launch(executable: shell,
                                 arguments: ["/d", "/c", "pause >nul"])
    let child = try Host.spawn(config)
    let identifier = child.information.process
    var processes = PlatformProcesses()
    _ = processes.record(consume child)
    try processes.remove(identifier)
    let empty = processes.isEmpty
    #expect(empty)
  }
}
#endif
