// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsEventTests {
  @Test
  internal func startup() throws {
    let process = ProcessIdentifier(rawValue: 7)
    var control = WindowsDebugControl()
    var event = DEBUG_EVENT()
    event.dwDebugEventCode = DSX::CREATE_PROCESS_DEBUG_EVENT
    event.dwProcessId = 7
    event.dwThreadId = 11
    let created = try control.translate(&event, process: process)
    guard case .started(let thread) = created else {
      Issue.record("process creation must not complete attachment")
      return
    }
    #expect(thread.process == process)
    #expect(thread.thread.rawValue == 11)
    #expect(control.initial == false)
    guard case .image = control.deferred else {
      Issue.record("expected the executable image")
      return
    }
    event.dwDebugEventCode = DSX::EXCEPTION_DEBUG_EVENT
    event.u.Exception.ExceptionRecord.ExceptionCode = DSX::EXCEPTION_BREAKPOINT
    event.u.Exception.dwFirstChance = 1
    let stopped = try control.translate(&event, process: process)
    guard case .stopped(let stop) = stopped else {
      Issue.record("expected the initial breakpoint stop")
      return
    }
    #expect(stop.thread == thread)
    #expect(stop.reason == .breakpoint)
    #expect(control.initial == true)
  }

  @Test
  internal func translation() throws {
    let created = CreateEventW(nil, false, false, nil)
    let handle = try #require(created)
    defer { _ = CloseHandle(handle) }
    let process = ProcessIdentifier(rawValue: 7)
    var control = WindowsDebugControl()
    control.threads[11] = WindowsDebugThread(handle: handle)
    var event = DEBUG_EVENT()
    event.dwDebugEventCode = DSX::EXIT_THREAD_DEBUG_EVENT
    event.dwProcessId = 7
    event.dwThreadId = 11
    event.u.ExitThread.dwExitCode = 19
    let translated = try control.translate(&event, process: process)
    switch translated {
    case .terminated(let thread, let code):
      #expect(thread.process == process)
      #expect(thread.thread.rawValue == 11)
      #expect(code == 19)
    default:
      Issue.record("expected a thread exit")
    }
    // Translation must not close the handle before continuation succeeds.
    #expect(control.threads[11]?.handle == handle)
    var flags: DWORD = 0
    #expect(GetHandleInformation(handle, &flags))
  }

  @Test(arguments: [DSX::EXIT_THREAD_DEBUG_EVENT,
                    DSX::EXIT_PROCESS_DEBUG_EVENT])
  internal func retry(_ code: DWORD) throws {
    let created = CreateEventW(nil, false, false, nil)
    let handle = try #require(created)
    defer { _ = CloseHandle(handle) }
    var control = WindowsDebugControl()
    control.handle = handle
    control.threads[11] = WindowsDebugThread(handle: handle)
    var event = DEBUG_EVENT()
    event.dwDebugEventCode = code
    event.dwThreadId = 11
    // Process zero cannot own a debugger event: continuation must fail.
    control.pending = event
    #expect(throws: Debuggee.Error.self) {
      try control.continue(disposition: .handled)
    }
    #expect(control.pending?.dwDebugEventCode == code)
    #expect(control.handle == handle)
    #expect(control.threads[11]?.handle == handle)
    var flags: DWORD = 0
    #expect(GetHandleInformation(handle, &flags))
  }
}
#endif
