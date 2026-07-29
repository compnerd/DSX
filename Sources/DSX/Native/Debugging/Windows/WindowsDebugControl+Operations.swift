// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension WindowsDebugControl {
  // MARK: - Capabilities

  internal static var capabilities: DebugCapabilities {
    .allocation | .detachment | .executable | .libraries | .passthrough
        | .threads | .tib
  }

  internal static var interval: Int32? {
    nil
  }

  internal mutating func ignore(_: Debuggee.ExceptionMask)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  internal func watchpoints(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Int {
    guard self.process == process else {
      throw .process
    }
    return try HardwareBreakpoint.capacity ?? 0
  }

  internal mutating func libraries(_ enabled: Bool) {
    libraries = enabled
  }

  // MARK: - Lifecycle

  internal mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.native
    guard DebugActiveProcess(identifier) else {
      throw WindowsDebugControl.failure(GetLastError())
    }
    guard DebugSetProcessKillOnExit(false) else {
      let code = GetLastError()
      _ = DebugActiveProcessStop(identifier)
      throw WindowsDebugControl.failure(code)
    }
    self.process = process
    attaching = true
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let identifier = try owned(process)
    if stopped {
      for index in threads.indices {
        try threads.values[index].suspend()
      }
    } else {
      try awaken()
    }
    try `continue`(disposition: .handled)
    guard DebugActiveProcessStop(identifier) else {
      throw WindowsDebugControl.failure(GetLastError())
    }
    release()
    self = WindowsDebugControl()
  }

  internal mutating func discard(_: borrowing Debuggee.Fork)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  internal mutating func interrupt(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try owned(process)
    let access = PROCESS_CREATE_THREAD | PROCESS_QUERY_LIMITED_INFORMATION
    let raw = OpenProcess(access, false, identifier)
    guard let raw else {
      throw WindowsDebugControl.failure(GetLastError())
    }
    let handle = WindowsHandle(raw)
    guard DebugBreakProcess(handle.value) else {
      throw WindowsDebugControl.failure(GetLastError())
    }
    interrupting = true
  }

  internal mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try owned(process)
    let raw = OpenProcess(PROCESS_TERMINATE, false, identifier)
    guard let raw else {
      throw WindowsDebugControl.failure(GetLastError())
    }
    let handle = WindowsHandle(raw)
    guard TerminateProcess(handle.value, 1) else {
      throw WindowsDebugControl.failure(GetLastError())
    }
    try `continue`(disposition: .handled)
  }

  // MARK: - Execution

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    try prepare(actions)
    guard let process else {
      throw .state
    }
    for index in 0 ..< actions.count where actions[index].operation == .stop {
      if case .none = pending {
        try interrupt(process)
      }
      return
    }
    let action = try WindowsDebugControl.action(pending?.dwThreadId,
                                                process: process,
                                                actions: actions)
    for index in threads.indices {
      let thread = threads[index].key
      let identifier = WindowsDebugControl.identifier(thread, process: process)
      let action =
          try Debuggee.Continuation.Plan.resolve(identifier, actions: actions)
      try threads.values[index].configure(action)
    }
    fallback =
        try Debuggee.Continuation.Plan.fallback(process, actions: actions)
    executing = true
    let disposition: WindowsDebugDisposition =
        action?.signal == nil ? .handled : .unhandled
    try `continue`(disposition: disposition)
  }

  private static func action(_ thread: DWORD?, process: ProcessIdentifier,
                             actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) -> Debuggee.Continuation? {
    guard let thread else {
      return nil
    }
    let identifier = WindowsDebugControl.identifier(thread, process: process)
    return try Debuggee.Continuation.Plan.resolve(identifier, actions: actions)
  }

  // MARK: - Events

  internal mutating func event(blocking: Bool = false, output: Bool = true,
                               signals _: borrowing SignalSet = SignalSet())
      throws(Debuggee.Error) -> Debuggee.Event? {
    guard let process else {
      throw .state
    }
    while true {
      if let deferred {
        self.deferred = nil
        return try deliver(deferred)
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
        let token = try token()
        let event = try WindowsDebugControl.wait(token, blocking: blocking,
                                                 polling: polling)
        try stage(event)
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
      if let disposition = WindowsDebugControl.disposition(event) {
        try `continue`(disposition: disposition)
        continue
      }
      return try deliver(translate(&event, process: process))
    }
  }

  private mutating func deliver(_ event: Debuggee.Event)
      throws(Debuggee.Error) -> Debuggee.Event {
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

  private func token() throws(Debuggee.Error) -> WindowsDebugToken {
    if case .some = pending {
      return .ready
    }
    guard case .some = process else {
      throw .state
    }
    return .active
  }

  private static func wait(_ token: WindowsDebugToken, blocking: Bool,
                           polling: Bool) throws(Debuggee.Error)
      -> WindowsDebugPending {
    guard token == .active else {
      return WindowsDebugPending()
    }
    var event = DEBUG_EVENT()
    let timeout: DWORD = switch (blocking, polling) {
    case (false, _): 0
    case (true, false): INFINITE
    case (true, true): DWORD(Configuration.DebuggeePollInterval)
    }
    guard WaitForDebugEventEx(&event, timeout) else {
      let error = GetLastError()
      if error == ERROR_SEM_TIMEOUT {
        return WindowsDebugPending()
      }
      throw WindowsDebugControl.failure(error)
    }
    return WindowsDebugPending(event)
  }

  private mutating func stage(_ pending: WindowsDebugPending)
      throws(Debuggee.Error) {
    if let event = pending.event {
      guard case .some = process else {
        throw .state
      }
      let code = event.dwDebugEventCode
      let process = event.dwProcessId
      DSX.log("received Windows debug event \(code) for \(process)",
              level: .trace, channel: .process)
      self.pending = event
    }
  }

  // MARK: - Recovery

  internal mutating func recover() throws(Debuggee.Error) {
    try awaken()
    try `continue`(disposition: .handled)
    executing = false
    fallback = nil
  }

  internal mutating func discard(_: borrowing Debuggee.Event)
      throws(Debuggee.Error) {
    try `continue`(disposition: .handled)
    executing = true
  }

  internal mutating func close() throws(Debuggee.Error) {
    guard let process else {
      return release()
    }
    try detach(process, stopped: false)
  }

  // MARK: - Breakpoints

  internal mutating func breakpoint(_ process: ProcessIdentifier,
                                    site: borrowing BreakpointSite,
                                    thread: ProcessThreadIdentifier?,
                                    enabled: Bool) throws(Debuggee.Error) {
    _ = try owned(process)
    if enabled {
      breakpoints.update(site, thread: thread, enabled: true)
    }
    try configure(site, thread: thread, enabled: enabled)
    if enabled == false {
      breakpoints.update(site, thread: thread, enabled: false)
    }
  }

  private mutating func `continue`(disposition: WindowsDebugDisposition)
      throws(Debuggee.Error) {
    guard let event = pending else {
      return
    }
    guard ContinueDebugEvent(event.dwProcessId, event.dwThreadId,
                             disposition.value) else {
      throw WindowsDebugControl.failure(GetLastError())
    }
    pending = nil
  }

  private mutating func awaken() throws(Debuggee.Error) {
    for index in threads.indices {
      try threads.values[index].activate()
    }
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

  private mutating func translate(_ event: inout DEBUG_EVENT,
                                  process: ProcessIdentifier)
      throws(Debuggee.Error) -> Debuggee.Event {
    let thread = ThreadIdentifier(rawValue: UInt64(event.dwThreadId))
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    switch event.dwDebugEventCode {
    case CREATE_PROCESS_DEBUG_EVENT:
      let info = event.u.CreateProcessInfo
      let path = WindowsDebugControl.path(info.hFile)
      if let file = info.hFile {
        _ = CloseHandle(file)
      }
      if let handle = info.hProcess {
        self.handle = handle
      }
      if let handle = info.hThread {
        try insert(event.dwThreadId, handle: handle)
      }
      let raw = UInt64(UInt(bitPattern: info.lpBaseOfImage))
      images[raw] = path
      let image = Debuggee.ImageEvent(process: process, path: path,
                                      address: Debuggee.Address(rawValue: raw),
                                      action: .load)
      deferred = .image(image)
      if attaching {
        attaching = false
        return .stopped(Debuggee.Stop(thread: identifier, reason: .interrupt))
      }
      return .started(identifier)
    case CREATE_THREAD_DEBUG_EVENT:
      if let handle = event.u.CreateThread.hThread {
        try insert(event.dwThreadId, handle: handle)
      }
      return .started(identifier)
    case EXIT_THREAD_DEBUG_EVENT:
      close(event.dwThreadId)
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
      let hardware = code == EXCEPTION_BREAKPOINT && parameters >= 2
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
      let path = WindowsDebugControl.path(event.u.LoadDll.hFile)
      if let file = event.u.LoadDll.hFile {
        _ = CloseHandle(file)
      }
      let raw = UInt64(UInt(bitPattern: event.u.LoadDll.lpBaseOfDll))
      let address = Debuggee.Address(rawValue: raw)
      images[raw] = path
      let image = Debuggee.ImageEvent(process: process, path: path,
                                      address: address, action: .load)
      if WindowsPath.system(path) {
        return .image(image)
      }
      guard libraries, !path.isEmpty else {
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
      guard libraries, !path.isEmpty else {
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
    case EXCEPTION_BREAKPOINT, kStatusWX86Breakpoint:
      .breakpoint
    case EXCEPTION_SINGLE_STEP, kStatusWX86SingleStep:
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
        code == EXCEPTION_BREAKPOINT || code == kStatusWX86Breakpoint
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

  private static func path(_ handle: HANDLE?) -> String {
    guard let handle else {
      return ""
    }
    do throws(Debuggee.Error) {
      return try path(handle)
    } catch {
      DSX.log("failed to resolve debug image path: \(error)", level: .warning,
              channel: .process)
      return ""
    }
  }

  private static func path(_ handle: HANDLE) throws(Debuggee.Error) -> String {
    try WindowsPath.canonical(WindowsPath.resolve(handle, process: true))
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

  private mutating func close(_ identifier: DWORD) {
    if let thread = threads.removeValue(forKey: identifier) {
      _ = CloseHandle(thread.handle)
    }
  }

  private mutating func release() {
    if let reader {
      _ = CloseHandle(reader)
      self.reader = nil
    }
    if let writer {
      _ = CloseHandle(writer)
      self.writer = nil
    }
    if let console {
      ClosePseudoConsole(console)
      self.console = nil
    }
    output = nil
    if let handle {
      _ = CloseHandle(handle)
      self.handle = nil
    }
    for thread in threads.values {
      _ = CloseHandle(thread.handle)
    }
    threads.removeAll(keepingCapacity: true)
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
        throw WindowsDebugControl.failure(code)
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
      throw WindowsDebugControl.failure(GetLastError())
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

  private static func identifier(_ thread: DWORD, process: ProcessIdentifier)
      -> ProcessThreadIdentifier {
    ProcessThreadIdentifier(process: process,
                            thread: ThreadIdentifier(rawValue: UInt64(thread)))
  }

  private func owned(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> DWORD {
    guard self.process == process else {
      throw .process
    }
    return try process.native
  }

  internal static func failure(_ code: DWORD) -> Debuggee.Error {
    WindowsError.debuggee(code, invalid: .process)
  }
}

extension WindowsDebugThread {
  fileprivate mutating func configure(_ action: Debuggee.Continuation?)
      throws(Debuggee.Error) {
    guard let action else {
      try suspend()
      execution = .stopped
      return
    }
    switch action.operation {
    case .resume:
      try activate()
      execution = .running
    case .step:
      try activate()
      try WindowsContext.modify(handle, flags: CONTEXT_CONTROL) { context in
        WindowsContext.step(&context)
      }
      execution = .stepping
    case .stop:
      try suspend()
      execution = .stopped
    }
  }

  fileprivate mutating func suspend() throws(Debuggee.Error) {
    if suspended {
      return
    }
    let count = SuspendThread(handle)
    switch count {
    case kThreadSuspendFailure:
      throw WindowsDebugControl.failure(GetLastError())
    default:
      suspended = true
    }
  }

  fileprivate mutating func activate() throws(Debuggee.Error) {
    if suspended {
      let count = ResumeThread(handle)
      switch count {
      case kThreadSuspendFailure:
        throw WindowsDebugControl.failure(GetLastError())
      default:
        suspended = false
      }
    }
  }
}

#endif
