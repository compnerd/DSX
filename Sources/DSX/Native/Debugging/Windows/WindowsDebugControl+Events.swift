// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsDebugControl {
  // MARK: - Events

  internal mutating func event(blocking: Bool = false, output: Bool = true,
                               signals _: borrowing SignalSet = SignalSet())
      throws(Debuggee.Error) -> Debuggee.Event? {
    guard let process else {
      throw .state
    }
    while true {
      if let translated {
        let event = try deliver(translated)
        self.translated = nil
        return event
      }
      if let deferred {
        self.deferred = nil
        translated = deferred
        continue
      }
      if output, case .some = self.output {
        return .output(process)
      }
      while case .none = pending {
        if output, try capture() {
          return .output(process)
        }
        let polling = if output, blocking, case .some = reader {
          true
        } else {
          false
        }
        try wait(blocking: blocking, polling: polling)
        if case .some = pending {
          break
        }
        guard blocking else {
          break
        }
      }
      if output, try capture() {
        return .output(process)
      }
      guard var event = pending else {
        return nil
      }
      if let disposition = WindowsDebugDisposition(event) {
        try `continue`(disposition: disposition)
        continue
      }
      defer {
        pending = event
      }
      translated = try translate(&event, process: process)
    }
  }

  private mutating func deliver(_ event: Debuggee.Event) throws(Debuggee.Error)
      -> Debuggee.Event {
    switch event {
    case .stopped:
      guard let thread = pending?.dwThreadId else {
        throw .state
      }
      halt(thread)
      executing = false
      fallback = nil
    case .exited:
      try `continue`(disposition: .handled)
      release()
      self = WindowsDebugControl()
    case .executed, .forked:
      executing = false
      fallback = nil
    case .image:
      if case .some = deferred {
        return event
      }
      try `continue`(disposition: .handled)
    case .output, .started, .terminated:
      try `continue`(disposition: .handled)
    }
    return event
  }

  private mutating func wait(blocking: Bool, polling: Bool)
      throws(Debuggee.Error) {
    var event = DEBUG_EVENT()
    let timeout: DWORD = switch (blocking, polling) {
    case (false, _): 0
    case (true, false): INFINITE
    case (true, true): DWORD(Configuration.DebuggeePollInterval)
    }
    guard WaitForDebugEventEx(&event, timeout) else {
      let error = GetLastError()
      if error == ERROR_SEM_TIMEOUT {
        return
      }
      throw Debuggee.Error(process: error)
    }
    let code = event.dwDebugEventCode
    let process = event.dwProcessId
    DSX.log("received Windows debug event \(code) for \(process)",
            level: .trace, channel: .process)
    pending = event
  }

  @inline(never)
  internal mutating func `continue`(disposition: WindowsDebugDisposition)
      throws(Debuggee.Error) {
    guard let event = pending else {
      return
    }
    guard ContinueDebugEvent(event.dwProcessId, event.dwThreadId,
                             disposition.value) else {
      throw Debuggee.Error(process: GetLastError())
    }
    // Exit continuation closes the event-provided handles in the debugger.
    // Forget them only after success; detach still needs explicit disposal.
    switch event.dwDebugEventCode {
    case EXIT_PROCESS_DEBUG_EVENT:
      handle = nil
      threads.removeAll(keepingCapacity: true)
    case EXIT_THREAD_DEBUG_EVENT:
      threads.removeValue(forKey: event.dwThreadId)
    default:
      break
    }
    pending = nil
    translated = nil
  }

  private mutating func halt(_ thread: DWORD) {
    for index in threads.indices {
      let identifier = threads[index].key
      let stepped = identifier == thread &&
          threads[index].value.execution == .stepping
      threads.values[index].execution = stepped ? .stepped : .stopped
    }
  }

  // MARK: - Event Translation

  internal mutating func translate(_ event: inout DEBUG_EVENT,
                                   process: ProcessIdentifier)
      throws(Debuggee.Error) -> Debuggee.Event {
    let identifier = ProcessThreadIdentifier(event.dwThreadId, process: process)
    switch event.dwDebugEventCode {
    case CREATE_PROCESS_DEBUG_EVENT:
      let info = event.u.CreateProcessInfo
      let raw = UInt64(UInt(bitPattern: info.lpBaseOfImage))
      let path = image(&event.u.CreateProcessInfo.hFile, at: raw)
      if let handle = info.hProcess {
        self.handle = handle
      }
      if let handle = info.hThread {
        try insert(event.dwThreadId, handle: handle)
      }
      let image = Debuggee.ImageEvent(process: process, path: path,
                                      address: Debuggee.Address(rawValue: raw),
                                      action: .load)
      deferred = .image(image)
      // Launch and attach both stop at the initial breakpoint, after Windows
      // has delivered its process, thread, and image inventory.
      return .started(identifier)
    case CREATE_THREAD_DEBUG_EVENT:
      if let handle = event.u.CreateThread.hThread {
        try insert(event.dwThreadId, handle: handle)
      }
      return .started(identifier)
    case EXIT_THREAD_DEBUG_EVENT:
      let code = CInt(bitPattern: event.u.ExitThread.dwExitCode)
      return .terminated(identifier, code)
    case EXIT_PROCESS_DEBUG_EVENT:
      let code = CInt(bitPattern: event.u.ExitProcess.dwExitCode)
      return .exited(process, .exited(code))
    case EXCEPTION_DEBUG_EVENT:
      let record = event.u.Exception.ExceptionRecord
      let code = record.ExceptionCode
      let parameters = record.NumberParameters
      let location = UInt64(UInt(bitPattern: record.ExceptionAddress))
      let hardware = record.hardware
      let raw = if hardware {
        UInt64(record.ExceptionInformation.1)
      } else {
        location
      }
      let message =
          "exception \(code) at \(location), \(parameters) parameters, " +
          "address \(raw)"
      DSX.log(message, level: .trace, channel: .process)
      let address = Debuggee.Address(rawValue: raw)
      let reason = reason(code, hardware: hardware)
      let data = Debuggee.ExceptionData(count: Int(parameters)) { index in
        withUnsafeBytes(of: record.ExceptionInformation) { values in
          let offset = index * MemoryLayout<ULONG_PTR>.stride
          return UInt64(values.loadUnaligned(fromByteOffset: offset,
                                             as: ULONG_PTR.self))
        }
      }
      let fault = Debuggee.Fault(address: address, code: UInt64(code),
                                 data: data, domain: .windows)
      let chance: Debuggee.ExceptionChance =
          event.u.Exception.dwFirstChance == 0 ? .second : .first
      return .stopped(Debuggee.Stop(thread: identifier, reason: reason,
                                    fault: fault, chance: chance))
    case LOAD_DLL_DEBUG_EVENT:
      let raw = UInt64(UInt(bitPattern: event.u.LoadDll.lpBaseOfDll))
      let path = image(&event.u.LoadDll.hFile, at: raw)
      let address = Debuggee.Address(rawValue: raw)
      let image = Debuggee.ImageEvent(process: process, path: path,
                                      address: address, action: .load)
      if WindowsPath.system(path) {
        return .image(image)
      }
      // Startup images precede the loader breakpoint. Publish the image, but
      // do not let a library notification complete the initial launch stop.
      guard initial, libraries, !path.isEmpty else {
        return .image(image)
      }
      deferred = .stopped(Debuggee.Stop(thread: identifier, reason: .library))
      return .image(image)
    case UNLOAD_DLL_DEBUG_EVENT:
      let raw = UInt64(UInt(bitPattern: event.u.UnloadDll.lpBaseOfDll))
      let address = Debuggee.Address(rawValue: raw)
      let path = images.removeValue(forKey: raw) ?? ""
      let image = Debuggee.ImageEvent(process: process, path: path,
                                      address: address, action: .unload)
      if WindowsPath.system(path) {
        return .image(image)
      }
      guard initial, libraries, !path.isEmpty else {
        return .image(image)
      }
      deferred = .stopped(Debuggee.Stop(thread: identifier, reason: .library))
      return .image(image)
    case OUTPUT_DEBUG_STRING_EVENT:
      output(event.u.DebugString)
      return .output(process)
    default:
      let code = UInt64(event.dwDebugEventCode)
      return .stopped(Debuggee.Stop(thread: identifier,
                                    reason: .exception(code)))
    }
  }

  internal static func exception(_ code: DWORD) -> Debuggee.StopReason {
    switch code {
    case EXCEPTION_BREAKPOINT, STATUS_WX86_BREAKPOINT:
      .breakpoint
    case EXCEPTION_SINGLE_STEP, STATUS_WX86_SINGLE_STEP:
      .trace
    case EXCEPTION_ACCESS_VIOLATION:
      .exception(UInt64(code))
    default:
      .exception(UInt64(code))
    }
  }

  private mutating func reason(_ code: DWORD, hardware: Bool)
      -> Debuggee.StopReason {
    let breakpoint =
        code == EXCEPTION_BREAKPOINT || code == STATUS_WX86_BREAKPOINT
    switch (breakpoint, hardware, initial, interrupting) {
    case (true, false, false, _):
      initial = true
      return .breakpoint
    case (true, false, true, true):
      interrupting = false
      return .interrupt
    default:
      return WindowsDebugControl.exception(code, hardware: hardware)
    }
  }

  @inline(never)
  private mutating func image(_ file: inout HANDLE?, at address: UInt64)
      -> String {
    let handle = file
    file = nil
    defer {
      if let handle {
        _ = CloseHandle(handle)
      }
    }
    let path = if let handle {
      WindowsDebugControl.path(handle)
    } else {
      images[address] ?? ""
    }
    images[address] = path
    return path
  }

  private static func path(_ handle: HANDLE) -> String {
    do throws(Debuggee.Error) {
      return try WindowsPath.canonical(WindowsPath.resolve(handle,
                                                           process: true))
    } catch {
      DSX.log("failed to resolve debug image path: \(error)", level: .warning,
              channel: .process)
      return ""
    }
  }

  private mutating func insert(_ identifier: DWORD, handle: HANDLE)
      throws(Debuggee.Error) {
    threads[identifier] = WindowsDebugThread(handle: handle)
    try restore(identifier)
    if executing, interrupting == false {
      guard var thread = threads[identifier] else {
        throw .thread
      }
      try thread.configure(fallback)
      threads[identifier] = thread
    }
  }

  // MARK: - Input and Output

  private mutating func capture() throws(Debuggee.Error) -> Bool {
    guard let reader else {
      return false
    }
    var available: DWORD = 0
    guard PeekNamedPipe(reader, nil, 0, nil, &available, nil) else {
      let code = GetLastError()
      guard code == ERROR_BROKEN_PIPE else {
        throw Debuggee.Error(process: code)
      }
      _ = CloseHandle(reader)
      self.reader = nil
      return false
    }
    guard available > 0 else {
      return false
    }
    var pending = Debuggee.Output()
    let capacity = min(Int(available), Configuration.OutputCapacity)
    let count = withUnsafeMutableBytes(of: &pending.bytes) { buffer in
      var count: DWORD = 0
      let status =
          ReadFile(reader, buffer.baseAddress, DWORD(capacity), &count, nil)
      return status ? Int(count) : -1
    }
    guard count >= 0 else {
      throw Debuggee.Error(process: GetLastError())
    }
    guard count > 0 else {
      return false
    }
    pending.count = count
    output = pending
    DSX.log("captured \(count) bytes of debuggee output", level: .trace,
            channel: .process)
    return true
  }
}
#endif
