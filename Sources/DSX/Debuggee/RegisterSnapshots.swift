// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct RegisterSnapshots: ~Copyable, Sendable {
  private var entries = Array<(identifier: UInt64, snapshot: SavedRegisters)>()
  private var sequence: UInt32 = 0

  internal var isEmpty: Bool { entries.isEmpty }

  @inline(__always)
  internal mutating func record(_ snapshot: consuming SavedRegisters)
      throws(Debuggee.Error) -> UInt64 {
    guard sequence < UInt32.max else {
      throw .state
    }
    sequence += 1
    let identifier = UInt64(sequence)
    entries.append((identifier: identifier, snapshot: consume snapshot))
    return identifier
  }

  @inline(__always)
  internal mutating func take(_ identifier: UInt64) throws(Debuggee.Error)
      -> SavedRegisters {
    guard let index = entries.firstIndex(where: { entry in
      entry.identifier == identifier
    }) else {
      throw .register
    }
    return entries.remove(at: index).snapshot
  }

  @inline(never)
  internal mutating func discard(_ process: ProcessIdentifier,
                                 thread: ThreadIdentifier? = nil) {
    entries.removeAll { entry in
      let candidate = entry.snapshot.thread
      return candidate.process == process &&
          (thread == nil || candidate.thread == thread)
    }
  }

  @inline(__always)
  internal mutating func clear() {
    entries.removeAll()
  }
}
