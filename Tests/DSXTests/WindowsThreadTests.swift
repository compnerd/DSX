// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsThreadTests {
  @Test
  internal func terminated() throws {
    let raw = CreateThread(nil, 0, { _ in 0 }, nil, 0, nil)
    let handle = try #require(raw)
    defer { _ = CloseHandle(handle) }
    try #require(WaitForSingleObject(handle, 1000) == DSX::WAIT_OBJECT_0)
    let thread = GetThreadId(handle)
    var control = WindowsDebugControl()
    control.process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    control.threads[thread] = WindowsDebugThread(handle: handle)
    let actions = Array<Debuggee.Continuation>()
    try control.resume(actions.span)
    #expect(control.threads[thread]?.suspended == false)
  }

  @Test
  internal func denied() throws {
    let thread = GetCurrentThreadId()
    let access = DSX::THREAD_QUERY_LIMITED_INFORMATION
    let handle = try #require(OpenThread(access, false, thread))
    defer { _ = CloseHandle(handle) }
    var control = WindowsDebugControl()
    control.process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    control.threads[thread] = WindowsDebugThread(handle: handle)
    let actions = Array<Debuggee.Continuation>()
    #expect(throws: Debuggee.Error.access) {
      try control.resume(actions.span)
    }
    #expect(control.threads[thread]?.suspended == false)
  }

  @Test
  internal func name() throws {
    let handle = GetCurrentThread()
    var previous: PWSTR?
    try #require(GetThreadDescription(handle, &previous) >= 0)
    defer {
      _ = SetThreadDescription(handle, previous)
      _ = LocalFree(previous)
    }
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let thread = ThreadIdentifier(rawValue: UInt64(GetCurrentThreadId()))
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    for name in ["ThreadName", "worker α", ""] {
      let status = (Array(name.utf16) + [0]).withUnsafeBufferPointer {
        SetThreadDescription(handle, $0.baseAddress)
      }
      try #require(status >= 0)
      let expected = name.isEmpty ? nil : name
      #expect(try identifier.info.name == expected)
    }
  }

  @Test
  internal func tib() throws(Debuggee.Error) {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let thread = ThreadIdentifier(rawValue: UInt64(GetCurrentThreadId()))
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    let address = try identifier.tib
    #expect(address.rawValue > 0)
  }
}
#endif
