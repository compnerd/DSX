// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct DeadlineTests {
  @Test
  internal func bounds() {
    let deadline = Deadline(milliseconds: 10, now: UInt64.max - 10)
    #expect(deadline.remaining(at: UInt64.max - 11) == 10)
    #expect(deadline.remaining(at: UInt64.max - 1) == 1)
    #expect(deadline.remaining(at: UInt64.max) == 0)
  }

  @Test
  internal func units() {
    let deadline = Deadline(seconds: 1, now: 100)
    #expect(deadline.remaining(at: 1099) == 1)
    #expect(deadline.remaining(at: 1100) == 0)
    #expect(deadline.remaining(at: 1101) == 0)
    let infinite = Deadline(seconds: UInt64.max, now: 0)
    #expect(infinite.remaining(at: 0) == UInt64.max)
  }

  @Test
  internal func zero() {
    #expect(Deadline(milliseconds: 0, now: 100).remaining(at: 100) == 0)
    #expect(Deadline(seconds: 0, now: 100).remaining(at: 100) == UInt64.max)
  }
}
