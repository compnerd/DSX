// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(i386)
internal import Testing
@testable internal import DSX

@Suite
internal struct WindowsMutexTests {
  private enum Failure: Error {
    case expected
  }

  private final class Counter: Sendable {
    fileprivate let value = Mutex(0)
  }

  private struct Token: ~Copyable, Sendable {
    fileprivate let counter: Counter

    deinit {
      counter.value.withLock { $0 += 1 }
    }
  }

  @Test
  internal func throwing() {
    let mutex = Mutex(0)
    do throws(Failure) {
      try mutex.withLock { value throws(Failure) in
        value = 1
        throw .expected
      }
      Issue.record("The closure must propagate its error")
    } catch {}
    #expect(mutex.withLock { $0 } == 1)
    mutex.withLock { $0 += 1 }
    #expect(mutex.withLock { $0 } == 2)
  }

  @Test
  internal func contention() async {
    let counter = Counter()
    await withTaskGroup(of: Void.self) { group in
      for _ in 0 ..< 8 {
        group.addTask {
          for _ in 0 ..< 10000 {
            counter.value.withLock { $0 += 1 }
          }
        }
      }
    }
    #expect(counter.value.withLock { $0 } == 80000)
  }

  @Test
  internal func lifetime() {
    let counter = Counter()
    do {
      let mutex = Mutex(Token(counter: counter))
      mutex.withLock { _ in }
      #expect(counter.value.withLock { $0 } == 0)
    }
    #expect(counter.value.withLock { $0 } == 1)
  }
}
#endif
