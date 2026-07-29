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
    if let capacity = try HardwareBreakpoint.capacity {
      return capacity
    }
    guard pending != nil, let thread = threads.values.first else {
      throw .thread
    }
    return try thread.watchpoints()
  }

  internal mutating func libraries(_ enabled: Bool) {
    libraries = enabled
  }

  // MARK: - Lifecycle

  internal mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.native
    guard DebugActiveProcess(identifier) else {
      throw Debuggee.Error(process: GetLastError())
    }
    guard DebugSetProcessKillOnExit(false) else {
      let code = GetLastError()
      _ = DebugActiveProcessStop(identifier)
      throw Debuggee.Error(process: code)
    }
    self.process = process
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    if stopped {
      var next = threads.startIndex
      while next != threads.endIndex {
        let index = next
        threads.formIndex(after: &next)
        try threads.values[index].suspend()
      }
    } else {
      try awaken()
    }
    try `continue`(disposition: .handled)
    guard DebugActiveProcessStop(identifier) else {
      throw Debuggee.Error(process: GetLastError())
    }
    release()
  }

  internal mutating func discard(_: borrowing Debuggee.Fork)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  internal mutating func interrupt(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    let access = PROCESS_CREATE_THREAD | PROCESS_QUERY_LIMITED_INFORMATION
    let raw = OpenProcess(access, false, identifier)
    guard let raw else {
      throw Debuggee.Error(process: GetLastError())
    }
    let handle = WindowsHandle(raw)
    guard DebugBreakProcess(handle.value) else {
      throw Debuggee.Error(process: GetLastError())
    }
    interrupting = true
  }

  @inline(never)
  internal mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    let raw = OpenProcess(PROCESS_TERMINATE, false, identifier)
    guard let raw else {
      throw Debuggee.Error(process: GetLastError())
    }
    let handle = WindowsHandle(raw)
    guard TerminateProcess(handle.value, 1) else {
      throw Debuggee.Error(process: GetLastError())
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
    let action = action(actions)
    var next = threads.startIndex
    while next != threads.endIndex {
      let index = next
      threads.formIndex(after: &next)
      let thread = threads[index].key
      let identifier = ProcessThreadIdentifier(thread, process: process)
      let action = actions.action(identifier)
      try threads.values[index].configure(action)
    }
    fallback = actions.action(process)
    executing = true
    let disposition: WindowsDebugDisposition =
        action?.signal == nil ? .handled : .unhandled
    try `continue`(disposition: disposition)
  }

  internal mutating func prepare(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let process else {
      throw .state
    }
    var next = threads.startIndex
    while next != threads.endIndex {
      let index = next
      threads.formIndex(after: &next)
      let thread = threads[index].key
      let identifier = ProcessThreadIdentifier(thread, process: process)
      guard let action = actions.action(identifier),
          action.operation != .stop else {
        continue
      }
      if threads[index].value.reply != nil ||
          pending?.dwThreadId == thread &&
          pending?.dwDebugEventCode == EXCEPTION_DEBUG_EVENT {
        try prepare(threads[index].value)
      }
      if threads[index].value.reply != nil {
        threads.values[index].reply =
            action.signal == nil ? .handled : .unhandled
      }
    }
  }

  private func action(_ actions: borrowing Debuggee.Continuations)
      -> Debuggee.Continuation? {
    guard let thread = pending?.dwThreadId, let process else {
      return nil
    }
    let identifier = ProcessThreadIdentifier(thread, process: process)
    return actions.action(identifier)
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
    _ = try process.owned(by: self.process)
    if enabled {
      breakpoints.update(site, thread: thread, enabled: true)
    }
    try configure(site, thread: thread, enabled: enabled)
    if enabled == false {
      breakpoints.update(site, thread: thread, enabled: false)
    }
  }

  private mutating func awaken() throws(Debuggee.Error) {
    var next = threads.startIndex
    while next != threads.endIndex {
      let index = next
      threads.formIndex(after: &next)
      if threads[index].value.reply != nil {
        threads.values[index].reply = .handled
      }
      try threads.values[index].activate()
    }
  }

  @inline(never)
  internal mutating func release() {
    if let reader {
      _ = CloseHandle(reader)
    }
    if let writer {
      _ = CloseHandle(writer)
    }
    if let console {
      ClosePseudoConsole(console)
    }
    if let handle {
      _ = CloseHandle(handle)
    }
    for thread in threads.values {
      _ = CloseHandle(thread.handle)
    }
    self = WindowsDebugControl()
  }
}
#endif
