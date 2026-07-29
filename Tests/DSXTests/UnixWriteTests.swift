// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
internal import Testing
@testable internal import DSX
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#else
internal import Glibc
#endif

@Suite(.serialized)
internal struct UnixWriteTests {
  private struct Outcome {
    fileprivate let seed: Int
    fileprivate let result: Int
    fileprivate let error: CInt
    fileprivate let prior: CInt
    fileprivate let pending: CInt
    fileprivate let blocked: CInt
    fileprivate let waited: CInt
    fileprivate let restored: CInt
  }

  private struct Context {
    fileprivate let descriptor: CInt
    fileprivate let inherited: Bool
    fileprivate let seeded: Bool
    fileprivate var outcome: Outcome?
  }

#if os(anyAppleOS)
  private typealias Start =
      @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
#else
  private typealias Start =
      @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
#endif

#if os(anyAppleOS)
  private static let start: Start = { pointer in
    let context = pointer.assumingMemoryBound(to: Context.self)
    context.pointee.outcome =
        UnixWriteTests.run(context.pointee.descriptor,
                           inherited: context.pointee.inherited,
                           seeded: context.pointee.seeded)
    return nil
  }
#else
  private static let start: Start = { pointer in
    guard let pointer else {
      return nil
    }
    let context = pointer.assumingMemoryBound(to: Context.self)
    context.pointee.outcome =
        UnixWriteTests.run(context.pointee.descriptor,
                           inherited: context.pointee.inherited,
                           seeded: context.pointee.seeded)
    return nil
  }
#endif

  @Test(arguments: [(false, false), (true, false), (true, true)])
  internal func disconnected(_ fixture: (Bool, Bool)) async throws {
    var descriptors: InlineArray<2, CInt> = [-1, -1]
    let status = withUnsafeMutablePointer(to: &descriptors) { descriptors in
      descriptors.withMemoryRebound(to: CInt.self, capacity: 2) { values in
        pipe(values)
      }
    }
    try #require(status == 0)
    _ = DSX::close(descriptors[0])
    defer { _ = DSX::close(descriptors[1]) }
    // A concurrent spawn may have inherited the reader before it was closed.
    // Wait for every reader to close before testing the disconnected writer.
    var descriptor =
        pollfd(fd: descriptors[1], events: Int16(POLLOUT), revents: 0)
    let disconnected = Int16(POLLERR | POLLHUP)
    for _ in 0 ..< 100 {
      try #require(poll(&descriptor, 1, 0) >= 0)
      if descriptor.revents & disconnected > 0 {
        break
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    try #require(descriptor.revents & disconnected > 0)
    try exercise(descriptors[1], inherited: fixture.0, seeded: fixture.1)
  }

  private func exercise(_ descriptor: CInt, inherited: Bool, seeded: Bool)
      throws {
    let context = UnsafeMutablePointer<Context>.allocate(capacity: 1)
    context.initialize(to: Context(descriptor: descriptor, inherited: inherited,
                                   seeded: seeded, outcome: nil))
    defer {
      context.deinitialize(count: 1)
      context.deallocate()
    }
#if os(anyAppleOS)
    var thread: pthread_t?
    try #require(pthread_create(&thread, nil, UnixWriteTests.start,
                                context) == 0)
    let joined = try #require(thread)
    try #require(pthread_join(joined, nil) == 0)
#else
    var thread = pthread_t()
    try #require(pthread_create(&thread, nil, UnixWriteTests.start,
                                context) == 0)
    try #require(pthread_join(thread, nil) == 0)
#endif
    let outcome = try #require(context.pointee.outcome)
#if os(anyAppleOS)
    #expect(outcome.seed == 0)
#else
    #expect((outcome.seed == -1) == seeded)
#endif
    #expect(outcome.result == -1)
    #expect(outcome.error == EPIPE)
    #expect(outcome.pending == outcome.prior)
    #expect((outcome.blocked == 1) == inherited)
    #expect(outcome.waited == 0)
    #expect(outcome.restored == 0)
  }

  private static func run(_ descriptor: CInt, inherited: Bool, seeded: Bool)
      -> Outcome? {
    var signals = sigset_t()
    sigemptyset(&signals)
    sigaddset(&signals, SIGPIPE)
    var previous = sigset_t()
    let operation = inherited ? SIG_BLOCK : SIG_UNBLOCK
    guard pthread_sigmask(operation, &signals, &previous) == 0 else {
      return nil
    }
    let bytes: InlineArray<1, UInt8> = [0]
    var seed = 0
    if seeded {
#if os(anyAppleOS)
      seed = Int(pthread_kill(pthread_self(), SIGPIPE))
#else
      seed = bytes.span.withUnsafeBytes {
        DSX::write(descriptor, $0.baseAddress, $0.count)
      }
#endif
    }
    // Darwin discards an ignored SIGPIPE even when it is blocked; Linux may
    // retain it. Verify preservation of the actual pending state on either OS.
    var prior = sigset_t()
    guard sigpending(&prior) == 0 else {
      _ = pthread_sigmask(SIG_SETMASK, &previous, nil)
      return nil
    }
    let seeded = sigismember(&prior, SIGPIPE)
    let result = bytes.span.withUnsafeBytes {
      DSX::write(descriptor, $0.baseAddress, $0.count, suppressing: SIGPIPE)
    }
    let error = errno
    var pending = sigset_t()
    var status = sigpending(&pending)
    let signal = status == 0 ? sigismember(&pending, SIGPIPE) : -1
    var current = sigset_t()
    status = pthread_sigmask(SIG_BLOCK, nil, &current)
    let blocked = status == 0 ? sigismember(&current, SIGPIPE) : -1
    var waited: CInt = 0
    if inherited, signal == 1 {
      var received: CInt = 0
      waited = sigwait(&signals, &received)
    }
    let restored = pthread_sigmask(SIG_SETMASK, &previous, nil)
    return Outcome(seed: seed, result: result, error: error, prior: seeded,
                   pending: signal, blocked: blocked, waited: waited,
                   restored: restored)
  }
}
#endif
