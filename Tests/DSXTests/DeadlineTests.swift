// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct DeadlineTests {
  @Test
  internal func bounds() {
    let start = Duration.milliseconds(UInt64.max - 10)
    let deadline = Deadline(.milliseconds(10), now: start)
    #expect(deadline.remaining(at: start - .milliseconds(1))
        == .milliseconds(10))
    #expect(deadline.remaining(at: start + .milliseconds(9))
        == .milliseconds(1))
    #expect(deadline.remaining(at: start + .milliseconds(10)) == .zero)
  }

  @Test
  internal func units() {
    let deadline = Deadline(.seconds(1), now: .milliseconds(100))
    #expect(deadline.remaining(at: .milliseconds(1099)) == .milliseconds(1))
    #expect(deadline.remaining(at: .milliseconds(1100)) == .zero)
    #expect(deadline.remaining(at: .milliseconds(1101)) == .zero)
  }

  @Test
  internal func zero() {
    let start = Duration.seconds(1)
    #expect(Deadline(.zero, now: start).remaining(at: start) == .zero)
    #expect(Deadline(.seconds(-1), now: start).remaining(at: start) == .zero)
  }

  @Test
  internal func fractions() {
    let deadline = Deadline(.microseconds(1500), now: .zero)
    #expect(deadline.remaining(at: .milliseconds(1)) == .microseconds(500))
    #expect(deadline.remaining(at: .milliseconds(2)) == .zero)
  }

  @Test
  internal func large() {
    let duration = Duration.seconds(UInt64.max)
    let deadline = Deadline(duration, now: .zero)
    #expect(deadline.remaining(at: .seconds(1)) == duration - .seconds(1))
  }
}
