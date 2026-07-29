// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

extension HostProcessRecord {
  // Captured output is not an exit notification. Poll child status instead.
  internal var event: WaitHandle? { nil }

  internal func reap() throws(Debuggee.Error) -> Bool {
    if try NativeProcess.reap(information.process) {
      return true
    }
    if let monitor {
      // notification() made this owned descriptor nonblocking. Drain a bounded
      // burst so an active child cannot block on output or monopolize the loop.
      withUnsafeTemporaryAllocation(of: UInt8.self,
                                    capacity: Configuration.Process.Capacity,
                                    { buffer in
        for _ in 0 ..< Configuration.Process.Burst {
          let count =
              DSX::read(monitor.descriptor, buffer.baseAddress, buffer.count)
          if count <= 0 {
            break
          }
        }
      })
    }
    return false
  }

  internal func terminate() throws(Debuggee.Error) {
    try NativeProcess.terminate(information.process)
  }
}
#endif
