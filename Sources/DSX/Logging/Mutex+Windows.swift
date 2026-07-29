// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(i386)
private import DSXShims
private import WinSDK

// FIXME(#1): Swift 6.4 mislowers Synchronization.Mutex's stdcall SRW operations
// on x86. Shadow only that target's Mutex, letting Clang own the Windows ABI
// boundary.
internal struct Mutex<Value: ~Copyable & Sendable>:
    ~Copyable, @unchecked Sendable {
  private struct Storage: ~Copyable {
    fileprivate var lock: SRWLOCK
    fileprivate var value: Value
  }

  // A stable allocation keeps both the lock and protected value stationary.
  // All access to the value is serialized, justifying unchecked Sendable.
  private let storage: UnsafeMutablePointer<Storage>

  internal init(_ value: consuming Value) {
    storage = .allocate(capacity: 1)
    storage.initialize(to: Storage(lock: SRWLOCK(), value: value))
  }

  deinit {
    storage.deinitialize(count: 1)
    storage.deallocate()
  }

  internal func withLock<R: ~Copyable,
                         E: Error>(_ body: (inout Value) throws(E) -> R)
      throws(E) -> R {
    dsx_AcquireSRWLockExclusive(&storage.pointee.lock)
    defer { dsx_ReleaseSRWLockExclusive(&storage.pointee.lock) }
    return try body(&storage.pointee.value)
  }
}
#endif
