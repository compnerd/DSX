// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsImageTests {
  @Test
  internal func delivery() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let image = try process.image
    let path = try #require(image).path
    let file = withUTF16CString(path) { path in
#if arch(i386)
      DSX::CreateFileW(path, DSX::GENERIC_READ,
                       FILE_SHARE_READ | FILE_SHARE_DELETE, nil, OPEN_EXISTING,
                       FILE_ATTRIBUTE_NORMAL, nil)
#else
      WinSDK.CreateFileW(path, DSX::GENERIC_READ,
                         FILE_SHARE_READ | FILE_SHARE_DELETE, nil,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nil)
#endif
    }
    let handle = try #require(file)
    try #require(handle != DSX::INVALID_HANDLE_VALUE)
    var control = WindowsDebugControl()
    control.process = process
    var event = DEBUG_EVENT()
    event.dwDebugEventCode = LOAD_DLL_DEBUG_EVENT
    event.dwProcessId = GetCurrentProcessId()
    event.dwThreadId = GetCurrentThreadId()
    event.u.LoadDll.hFile = handle
    event.u.LoadDll.lpBaseOfDll = UnsafeMutableRawPointer(bitPattern: 0x1000)
    control.pending = event
    defer {
      if control.pending?.u.LoadDll.hFile != nil {
#if arch(i386)
        _ = DSX::CloseHandle(handle)
#else
        _ = WinSDK.CloseHandle(handle)
#endif
      }
    }
    // This process is not a debuggee, so continuation fails without a mock.
    for _ in 0 ..< 2 {
      do {
        _ = try control.event(output: false)
        Issue.record("continuation unexpectedly succeeded")
      } catch {
      }
      #expect(control.pending?.u.LoadDll.hFile == nil)
      var flags: DWORD = 0
      #expect(GetHandleInformation(handle, &flags) == false)
      guard case .image(let image) = control.translated else {
        Issue.record("failed delivery must retain the translated image")
        return
      }
      #expect(image.path.isEmpty == false)
      #expect(image.path != "replacement")
      control.images[0x1000] = "replacement"
    }
    control.pending = nil
    let delivered = try control.event(output: false)
    guard case .image(let image) = delivered else {
      Issue.record("expected the retained image")
      return
    }
    #expect(image.path != "replacement")
    #expect(control.translated == nil)
  }

  @Test
  internal func translation() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let image = try process.image
    let path = try #require(image).path
    let file = withUTF16CString(path) { path in
#if arch(i386)
      DSX::CreateFileW(path, DSX::GENERIC_READ,
                       FILE_SHARE_READ | FILE_SHARE_DELETE, nil, OPEN_EXISTING,
                       FILE_ATTRIBUTE_NORMAL, nil)
#else
      WinSDK.CreateFileW(path, DSX::GENERIC_READ,
                         FILE_SHARE_READ | FILE_SHARE_DELETE, nil,
                         OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nil)
#endif
    }
    let handle = try #require(file)
    try #require(handle != DSX::INVALID_HANDLE_VALUE)
    let thread = try #require(CreateEventW(nil, true, false, nil))
    defer {
#if arch(i386)
      _ = DSX::CloseHandle(thread)
#else
      _ = WinSDK.CloseHandle(thread)
#endif
    }
    var control = WindowsDebugControl()
    control.process = process
    let site = BreakpointSite(address: Debuggee.Address(rawValue: 0x1000),
                              size: 1, kind: .hardware)
    control.breakpoints.update(site, thread: nil, enabled: true)
    var event = DEBUG_EVENT()
    event.dwDebugEventCode = CREATE_PROCESS_DEBUG_EVENT
    event.dwProcessId = GetCurrentProcessId()
    event.dwThreadId = GetCurrentThreadId()
    event.u.CreateProcessInfo.hFile = handle
    event.u.CreateProcessInfo.hThread = thread
    event.u.CreateProcessInfo.lpBaseOfImage =
        UnsafeMutableRawPointer(bitPattern: 0x1000)
    control.pending = event
    defer {
      if control.pending?.u.CreateProcessInfo.hFile != nil {
#if arch(i386)
        _ = DSX::CloseHandle(handle)
#else
        _ = WinSDK.CloseHandle(handle)
#endif
      }
    }
    // A real event handle cannot provide a thread's register context.
    for _ in 0 ..< 2 {
      do {
        _ = try control.event(output: false)
        Issue.record("thread configuration unexpectedly succeeded")
      } catch {
      }
      #expect(control.pending?.u.CreateProcessInfo.hFile == nil)
      #expect(control.images[0x1000]?.isEmpty == false)
      #expect(control.translated == nil)
    }
  }

  @Test
  internal func snapshot() throws {
    let process = ProcessIdentifier(rawValue: 7)
    var control = WindowsDebugControl()
    control.process = process
    control.images[0x1000] = "S:\\pending.dll"
    var cursor = try control.images(process)
    control.images.removeValue(forKey: 0x1000)
    control.images[0x2000] = "S:\\replacement.dll"
    let pending = try cursor.next()
    let image = try #require(pending)
    #expect(image.path == "S:\\pending.dll")
    #expect(image.base.rawValue == 0x1000)
    let end = try cursor.next()
    #expect(end == nil)
    var replacement = try control.images(process)
    let next = try replacement.next()
    #expect(next?.path == "S:\\replacement.dll")
    let complete = try replacement.next()
    #expect(complete == nil)
  }

  @Test(arguments: [false, true], [false, true])
  internal func startup(_ initial: Bool, _ libraries: Bool) throws {
    let process = ProcessIdentifier(rawValue: 7)
    let address = Debuggee.Address(rawValue: 0x1000)
    let path = "S:\\fixture.dll"
    var control = WindowsDebugControl()
    control.initial = initial
    control.libraries = libraries
    control.images[address.rawValue] = path
    var event = DEBUG_EVENT()
    event.dwDebugEventCode = UNLOAD_DLL_DEBUG_EVENT
    event.dwProcessId = 7
    event.dwThreadId = 11
    event.u.UnloadDll.lpBaseOfDll = UnsafeMutableRawPointer(bitPattern: 0x1000)
    let result = try control.translate(&event, process: process)
    guard case .image(let image) = result else {
      Issue.record("startup must retain image events")
      return
    }
    #expect(image.path == path)
    #expect(image.address == address)
    #expect(image.action == .unload)
    #expect(control.images.isEmpty)
    if initial, libraries {
      guard case .stopped(let stop) = control.deferred else {
        Issue.record("expected a negotiated library stop after startup")
        return
      }
      #expect(stop.reason == .library)
    } else {
      #expect(control.deferred == nil)
    }
  }

  @Test
  internal func offsets() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let images = try process.images(.full)
    let image = try #require(images.first(where: { image in image.main }))
    let result = try process.image
    let selected = try #require(result)
    #expect(selected.path == image.path)
    #expect(selected.base == image.base)
    let info = try process.info
    let module = try Debuggee.Module(path: image.path)
    #expect(module.architecture == info.architecture)
    #expect(module.identity?.value.isEmpty == false)
    let storage = try NativeMappedFile(image.path)
    guard let view = try PEModule(storage.span()) else {
      Issue.record("expected a PE image")
      return
    }
    let preferred = try view.base
    let offsets = try image.offsets
    guard case .sections(let text, let data) = offsets else {
      Issue.record("Windows image offsets must use section relocation")
      return
    }
    #expect(text == image.base.rawValue &- preferred)
    #expect(data == text)
  }

  @Test
  internal func address() throws {
    let process = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let address = try process.address
    #expect(address == Debuggee.Address(rawValue: 0))
  }
}
#endif
