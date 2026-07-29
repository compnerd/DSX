// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal enum WindowsThreadExecution: Equatable, Sendable {
  case running
  case stepping
  case stepped
  case stopped
}

internal struct WindowsDebugThread: @unchecked Sendable {
  internal let handle: HANDLE
  internal var execution: WindowsThreadExecution
  internal var suspended: Bool

  internal init(handle: HANDLE, execution: WindowsThreadExecution = .running,
                suspended: Bool = false) {
    self.handle = handle
    self.execution = execution
    self.suspended = suspended
  }
}

internal struct WindowsDebugControl: ~Copyable, @unchecked Sendable {
  internal var process: ProcessIdentifier?
  internal var pending: DEBUG_EVENT?
  internal var handle: HANDLE?
  internal var threads = Dictionary<DWORD, WindowsDebugThread>()
  internal var breakpoints = ActiveBreakpoints()
  internal var fallback: Debuggee.Continuation?
  internal var executing = false
  internal var reader: HANDLE?
  internal var writer: HANDLE?
  internal var output: Debuggee.Output?
  internal var images = Dictionary<UInt64, String>()
  internal var deferred: Debuggee.Event?
  internal var attaching = false
  internal var initial = false
  internal var interrupting = false
  internal var libraries = false
  internal var console: HANDLE?
}

internal enum WindowsDebugToken: Equatable, Sendable {
  case active
  case ready
}

internal struct WindowsDebugPending: @unchecked Sendable {
  internal let event: DEBUG_EVENT?

  internal init(_ event: DEBUG_EVENT? = nil) {
    self.event = event
  }
}
#endif
