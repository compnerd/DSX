// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

extension HostProcessRecord {
  internal func reap() throws(Debuggee.Error) -> Bool {
    guard let monitor else {
      return true
    }
    return switch WaitForSingleObject(monitor.value, 0) {
    case WAIT_OBJECT_0: true
    case WAIT_TIMEOUT: false
    default: throw WindowsProcess.failure(GetLastError())
    }
  }

  internal func terminate() throws(Debuggee.Error) {
    if try reap() {
      return
    }
    guard let monitor else {
      return
    }
    guard TerminateProcess(monitor.value, 1) else {
      throw WindowsProcess.failure(GetLastError())
    }
    guard WaitForSingleObject(monitor.value, INFINITE) == WAIT_OBJECT_0 else {
      throw WindowsProcess.failure(GetLastError())
    }
  }
}
#endif
