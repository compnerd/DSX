// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  @inline(__always)
  internal mutating func save(_ thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> UInt64 {
    try snapshots.record(SavedRegisters(thread, control: control))
  }

  @inline(__always)
  internal mutating func restore(_ identifier: UInt64,
                                 thread: ProcessThreadIdentifier?)
      throws(Debuggee.Error) {
    let saved = try snapshots.take(identifier)
    let identifier = thread ?? saved.thread
    var snapshot = try NativeRegisterState(identifier, control: control)
    try snapshot.restore(saved)
    try snapshot.commit()
  }
}
