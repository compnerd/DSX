// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsThreadTests {
  @Test
  internal func released() throws {
    var control = WindowsDebugControl()
    defer { control.release() }
    let raw = CreateEventW(nil, false, false, nil)
    let handle = try #require(raw)
    control.reader = handle
    control.process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    control.pending = DEBUG_EVENT()
    control.cursor = control.threads.startIndex
    control.executing = true
    control.initial = true
    control.interrupting = true
    control.libraries = true
    control.images[1] = "image"
    control.release()
    #expect(control.process == nil)
    #expect(control.pending == nil)
    #expect(control.cursor == nil)
    #expect(control.reader == nil)
    #expect(control.executing == false)
    #expect(control.initial == false)
    #expect(control.interrupting == false)
    #expect(control.libraries == false)
    #expect(control.images.isEmpty)
    var flags: DWORD = 0
    let valid = GetHandleInformation(handle, &flags)
    let error = GetLastError()
    #expect(valid == false)
    #expect(error == DSX::ERROR_INVALID_HANDLE)
  }

  @Test
  internal func collection() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    var control = WindowsDebugControl()
    control.process = process
    for identifier in [DWORD(1), 2, 3] {
      var thread = WindowsDebugThread(handle: GetCurrentThread())
      thread.execution = identifier == 2 ? .stopped : .trapped
      thread.reply = .deferred
      control.threads[identifier] = thread
    }
    let snapshot = control.threads
    control.cursor = control.threads.startIndex
    var identifiers = Array<ProcessThreadIdentifier>()
    while let event = control.collect() {
      guard case .stopped(let stop) = event else {
        Issue.record("Expected a captured hardware stop")
        return
      }
      #expect(stop.reason == .trace)
      identifiers.append(stop.thread)
    }
    #expect(identifiers.count == 2)
    for identifier in [DWORD(1), 3] {
      let thread = ProcessThreadIdentifier(identifier, process: process)
      #expect(identifiers.contains(thread))
      #expect(control.threads[identifier]?.execution == .stopped)
      #expect(control.threads[identifier]?.reply == .deferred)
      #expect(snapshot[identifier]?.execution == .trapped)
    }
    #expect(control.collect() == nil)
    #expect(control.cursor == nil)
  }

  @Test(arguments: [false, true])
  internal func reply(_ forwarding: Bool) throws {
    let raw =
        CreateThread(nil, 0, { _ in 0 }, nil, DWORD(CREATE_SUSPENDED), nil)
    let handle = try #require(raw)
    defer {
      _ = ResumeThread(handle)
      _ = WaitForSingleObject(handle, 1000)
      _ = CloseHandle(handle)
    }
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let native = GetThreadId(handle)
    let identifier = ProcessThreadIdentifier(native, process: process)
    var control = WindowsDebugControl()
    control.process = process
    control.threads[native] =
        WindowsDebugThread(handle: handle, suspended: true)
    control.threads[native]?.reply = .deferred
    let stopped = Array<Debuggee.Continuation>()
    try control.prepare(stopped.span)
    #expect(control.threads[native]?.reply == .deferred)
    let action = Debuggee.Continuation(selection: .thread(identifier),
                                      operation: .resume,
                                      signal: forwarding ? 5 : nil)
    let actions = [action]
    try control.prepare(actions.span)
    let expected: WindowsDebugDisposition = forwarding ? .unhandled : .handled
    #expect(control.threads[native]?.reply == expected)
    #expect(control.threads[native]?.suspended == true)
    #expect(WaitForSingleObject(handle, 0) == DSX::WAIT_TIMEOUT)
  }

  @Test
  internal func terminated() throws {
    let raw = CreateThread(nil, 0, { _ in 0 }, nil, 0, nil)
    let handle = try #require(raw)
    defer { _ = CloseHandle(handle) }
    try #require(WaitForSingleObject(handle, 1000) == DSX::WAIT_OBJECT_0)
    #expect(try WindowsDebugThread(handle: handle).trapped == false)
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
