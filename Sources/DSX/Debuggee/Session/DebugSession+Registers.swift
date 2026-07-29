// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func save(_ thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> UInt64 {
    let saved = try SavedRegisters(thread, identifier: UInt64(sequence) + 1)
    guard sequence < UInt32.max else {
      throw .state
    }
    sequence += 1
    snapshots.append(saved)
    return saved.identifier
  }

  internal mutating func restore(_ identifier: UInt64,
                                 thread: ProcessThreadIdentifier?)
      throws(Debuggee.Error) {
    guard let index = snapshots.firstIndex(where: { snapshot in
      snapshot.identifier == identifier
    }) else {
      throw .register
    }
    let saved = snapshots.remove(at: index)
    let identifier = thread ?? saved.thread
    var snapshot = try NativeRegisterState(identifier)
    try snapshot.restore(saved)
    try snapshot.commit(identifier)
  }
}
