// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

/// Failure sentinel returned by `SuspendThread` and `ResumeThread`.
private let kThreadSuspendFailure = DWORD.max

// THREADINFOCLASS.ThreadIsTerminated (not exposed by the Windows SDK).
private let ThreadIsTerminated: CInt = 20

internal enum WindowsThreadExecution: Equatable, Sendable {
  case running
  case stepping
  case stopped
  case trapped
}

internal struct WindowsDebugThread: @unchecked Sendable {
  internal let handle: HANDLE
  internal var execution: WindowsThreadExecution
  internal var suspended: Bool
  internal var reply: WindowsDebugDisposition?

  internal init(handle: HANDLE, execution: WindowsThreadExecution = .running,
                suspended: Bool = false) {
    self.handle = handle
    self.execution = execution
    self.suspended = suspended
  }
}

extension WindowsDebugThread {
  internal var exited: Bool {
    get throws(Debuggee.Error) {
      // The handle is not signaled until exit completes. A terminating thread
      // can already reject context operations while its exit event is queued.
      var terminated: ULONG = 0
      let size = ULONG(MemoryLayout<ULONG>.size)
      let status = NtQueryInformationThread(handle, ThreadIsTerminated,
                                            &terminated, size, nil)
      guard status >= 0 else {
        throw Debuggee.Error(process: RtlNtStatusToDosError(status))
      }
      return terminated > 0
    }
  }

  @inline(never)
  internal mutating func configure(_ action: Debuggee.Continuation?)
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
      if try exited {
        return
      }
      var context = try CONTEXT(handle, flags: CONTEXT_CONTROL)
      context.step()
      try context.commit(to: handle)
      try activate()
      execution = .stepping
    case .stop:
      try suspend()
      execution = .stopped
    }
  }

  internal mutating func suspend() throws(Debuggee.Error) {
    if suspended {
      return
    }
    // A terminating thread cannot run again, but its exit event may still
    // be queued. SuspendThread conflates this state with access denied.
    let status = NtSuspendThread(handle, nil)
    if status == STATUS_THREAD_IS_TERMINATING {
      return
    }
    guard status >= 0 else {
      throw Debuggee.Error(process: RtlNtStatusToDosError(status))
    }
    suspended = true
  }

  internal mutating func activate() throws(Debuggee.Error) {
    if suspended, try exited == false {
      let count = ResumeThread(handle)
      switch count {
      case kThreadSuspendFailure:
        throw Debuggee.Error(process: GetLastError())
      default:
        suspended = false
      }
    }
  }
}
#endif
