// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) || os(FreeBSD) || os(OpenBSD)
extension NativeDebugControl {
  internal func watchpoints(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Int {
    guard self.process == process else {
      throw .process
    }
    return try HardwareBreakpoint.capacity ?? 0
  }

  internal mutating func discard(_: borrowing Debuggee.Fork)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  internal mutating func close() throws(Debuggee.Error) {
    guard let process else {
      return
    }
    try detach(process, stopped: false)
  }

  internal func complete(_: borrowing Debuggee.Event) throws(Debuggee.Error) {
  }

  internal func discard(_: borrowing Debuggee.Event) throws(Debuggee.Error) {
  }

  internal func syscalls(_ calls: consuming Array<UInt64>?)
      throws(Debuggee.Error) {
    guard calls == nil else {
      throw .unsupported
    }
  }
}
#endif
