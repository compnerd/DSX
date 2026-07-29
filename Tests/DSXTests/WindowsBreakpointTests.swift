// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(i386) || arch(x86_64))
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsBreakpointTests {
  @Test
  internal func partial() throws {
    let primary =
        CreateThread(nil, 0, { _ in 0 }, nil, DWORD(CREATE_SUSPENDED), nil)
    let first = try #require(primary)
    let secondary =
        CreateThread(nil, 0, { _ in 0 }, nil, DWORD(CREATE_SUSPENDED), nil)
    let second = try #require(secondary)
    defer {
      for handle in [first, second] {
        _ = ResumeThread(handle)
        _ = WaitForSingleObject(handle, 1000)
        _ = CloseHandle(handle)
      }
    }
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    var control = WindowsDebugControl()
    control.process = process
    control.handle = GetCurrentProcess()
    control.threads[GetThreadId(first)] = WindowsDebugThread(handle: first)
    control.threads[GetThreadId(second)] = WindowsDebugThread(handle: second)
    let keys = Array(control.threads.keys)
    let good = try #require(control.threads[keys[0]]?.handle)
    let saved = try #require(control.threads[keys[1]])
    // Replacing a value retains dictionary traversal order. The second update
    // fails after the first thread's debug registers have been programmed.
    control.threads[keys[1]] =
        WindowsDebugThread(handle: HANDLE(bitPattern: 1)!)
    var table = BreakpointTable()
    let site = BreakpointSite(address: Debuggee.Address(rawValue: 0x1000),
                              size: 4, kind: .watchpoint(.write))
    let identifier = try table.insert(process, site)
    for _ in 0 ..< 2 {
      #expect(throws: Debuggee.Error.self) {
        try table.enable(identifier, context: &control)
      }
      #expect(control.breakpoints.count == 1)
    }
    let flags = DSX::CONTEXT_DEBUG_REGISTERS
    let context = try WindowsContext.snapshot(good, flags: flags)
    #expect(context.Dr7 & 0xff == 1)
    #expect(throws: Debuggee.Error.self) {
      try table.remove(process, identifier, context: &control)
    }
    #expect(table.find(process, site) == identifier)
    control.threads[keys[1]] = saved
    try table.remove(process, identifier, context: &control)
    #expect(control.breakpoints.isEmpty)
    for handle in [first, second] {
      let context = try WindowsContext.snapshot(handle, flags: flags)
      #expect(context.Dr7 & 0xff == 0)
    }
  }

  @Test
  internal func invalid() throws {
    let thread =
        CreateThread(nil, 0, { _ in 0 }, nil, DWORD(CREATE_SUSPENDED), nil)
    let handle = try #require(thread)
    defer {
      _ = ResumeThread(handle)
      _ = WaitForSingleObject(handle, 1000)
      _ = CloseHandle(handle)
    }
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    var control = WindowsDebugControl()
    control.process = process
    control.handle = GetCurrentProcess()
    control.threads[GetThreadId(handle)] = WindowsDebugThread(handle: handle)
    var table = BreakpointTable()
    let site = BreakpointSite(address: Debuggee.Address(rawValue: 0x1000),
                              size: 3, kind: .watchpoint(.write))
    #expect(throws: Debuggee.Error.self) {
      _ = try table.insert(process, site, context: &control)
    }
    #expect(table.find(process, site) == nil)
    #expect(control.breakpoints.isEmpty)
  }

  @Test(arguments: [true, false])
  internal func sharing(_ reverse: Bool) throws {
    let thread =
        CreateThread(nil, 0, { _ in 0 }, nil, DWORD(CREATE_SUSPENDED), nil)
    let handle = try #require(thread)
    defer {
      _ = ResumeThread(handle)
      _ = WaitForSingleObject(handle, 1000)
      _ = CloseHandle(handle)
    }
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    var control = WindowsDebugControl()
    control.process = process
    control.handle = GetCurrentProcess()
    control.threads[GetThreadId(handle)] = WindowsDebugThread(handle: handle)
    var table = BreakpointTable()
    let address = Debuggee.Address(rawValue: 0x1000)
    let read =
        BreakpointSite(address: address, size: 4, kind: .watchpoint(.read))
    let both =
        BreakpointSite(address: address, size: 4, kind: .watchpoint(.readwrite))
    let first = try table.insert(process, read, capacity: 1, context: &control)
    let second = try table.insert(process, both, capacity: 1, context: &control)
    let flags = DSX::CONTEXT_DEBUG_REGISTERS
    var snapshot = try WindowsContext.snapshot(handle, flags: flags)
    #expect(snapshot.Dr7 & 0xff == 1)
    #expect(control.breakpoints.count == 1)
    try table.remove(process, reverse ? second : first, context: &control)
    snapshot = try WindowsContext.snapshot(handle, flags: flags)
    #expect(snapshot.Dr7 & 0xff == 1)
    try table.remove(process, reverse ? first : second, context: &control)
    snapshot = try WindowsContext.snapshot(handle, flags: flags)
    #expect(snapshot.Dr7 & 0xff == 0)
    #expect(control.breakpoints.isEmpty)
  }

  @Test
  internal func capacity() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    var table = BreakpointTable()
    let address = Debuggee.Address(rawValue: 0x1000)
    let read =
        BreakpointSite(address: address, size: 4, kind: .watchpoint(.read))
    let both =
        BreakpointSite(address: address, size: 4, kind: .watchpoint(.readwrite))
    _ = try table.insert(process, read, capacity: 2)
    _ = try table.insert(process, both, capacity: 2)
    let other = BreakpointSite(address: Debuggee.Address(rawValue: 0x2000),
                               size: 4, kind: .watchpoint(.write))
    _ = try table.insert(process, other, capacity: 2)
  }

  @Test
  internal func slots() throws {
    let thread =
        CreateThread(nil, 0, { _ in 0 }, nil, DWORD(CREATE_SUSPENDED), nil)
    let handle = try #require(thread)
    defer {
      _ = ResumeThread(handle)
      _ = WaitForSingleObject(handle, 1000)
      _ = CloseHandle(handle)
    }
    let address = Debuggee.Address(rawValue: 0x1000)
    let execution = BreakpointSite(address: address, size: 1, kind: .hardware)
    let byte =
        BreakpointSite(address: address, size: 1, kind: .watchpoint(.write))
    let word =
        BreakpointSite(address: address, size: 4, kind: .watchpoint(.write))
    try WindowsDebugControl.configure(execution, enabled: true, handle: handle)
    try WindowsDebugControl.configure(byte, enabled: true, handle: handle)
    try WindowsDebugControl.configure(word, enabled: true, handle: handle)
    let flags = DSX::CONTEXT_DEBUG_REGISTERS
    var context = try WindowsContext.snapshot(handle, flags: flags)
    #expect(context.Dr7 & 0x3f == 0x15)
    #expect(context.Dr0 == address.rawValue)
    #expect(context.Dr1 == address.rawValue)
    #expect(context.Dr2 == address.rawValue)
    try WindowsDebugControl.configure(byte, enabled: false, handle: handle)
    context = try WindowsContext.snapshot(handle, flags: flags)
    #expect(context.Dr7 & 0x3f == 0x11)
    #expect(context.Dr0 == address.rawValue)
    #expect(context.Dr1 == 0)
    #expect(context.Dr2 == address.rawValue)
    try WindowsDebugControl.configure(execution, enabled: false, handle: handle)
    try WindowsDebugControl.configure(word, enabled: false, handle: handle)
  }
}
#endif
