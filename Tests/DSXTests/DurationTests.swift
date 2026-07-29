// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct DurationTests {
  @Test
  internal func rounding() {
    #expect(Duration.zero.rounded(to: .milliseconds(1), rule: .up) == 0)
    #expect(Duration.seconds(-1).rounded(to: .milliseconds(1), rule: .up) == 0)
    #expect(Duration.nanoseconds(1).rounded(to: .milliseconds(1),
                                            rule: .up) == 1)
    #expect(Duration.microseconds(1001).rounded(to: .milliseconds(1),
                                                rule: .up) == 2)
    #expect(Duration.milliseconds(10).rounded(to: .milliseconds(1),
                                              rule: .up) == 10)
    #expect(Duration.microseconds(10_000).rounded(to: .microseconds(1),
                                                  rule: .up) == 10_000)
  }

  @Test
  internal func downward() {
    for value in [-1, 0, 1, 999, 1000, 1001, 1999, 2000] {
      let duration = Duration.microseconds(value)
      #expect(duration.rounded(to: .milliseconds(1), rule: .down)
          == UInt64(max(value, 0) / 1000))
    }
    let maximum = Duration(attoseconds: Int128.max)
    #expect(maximum.rounded(to: maximum, rule: .down) == 1)
    #expect(maximum.rounded(to: Duration(attoseconds: 1), rule: .down)
        == UInt64.max)
    let minimum = Duration(attoseconds: Int128.min)
    #expect(minimum.rounded(to: .milliseconds(1), rule: .down) == 0)
  }

  @Test
  internal func boundaries() {
    let maximum = Duration(attoseconds: Int128.max)
    let minimum = Duration(attoseconds: Int128.min)
    #expect(maximum.rounded(to: maximum, rule: .up) == 1)
    #expect(maximum.rounded(to: Duration(attoseconds: 1),
                            rule: .up) == UInt64.max)
    #expect(minimum.rounded(to: .milliseconds(1), rule: .up) == 0)
    for value in [999, 1000, 1001] {
      let duration = Duration.microseconds(value)
      #expect(duration.rounded(to: .milliseconds(1),
                               rule: .up) == UInt64((value + 999) / 1000))
    }
  }

  @Test
  internal func saturation() {
    #expect(Duration.seconds(UInt64.max).rounded(to: .milliseconds(1),
                                                 rule: .up) == UInt64.max)
    #expect(Duration.seconds(UInt64.max).rounded(to: .seconds(1),
                                                 rule: .up) == UInt64.max)
    #expect(Duration.milliseconds(UInt64.max).rounded(to: .milliseconds(1),
                                                      rule: .up)
        == UInt64.max)
  }
}
