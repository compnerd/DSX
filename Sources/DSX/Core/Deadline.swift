// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct Deadline {
  private let start: UInt64
  private let duration: UInt64

  internal init(seconds: UInt64, now: UInt64) {
    let (duration, overflow) = seconds.multipliedReportingOverflow(by: 1_000)
    self.init(milliseconds: seconds == 0 || overflow ? UInt64.max : duration,
              now: now)
  }

  internal init(milliseconds: UInt64, now: UInt64) {
    start = now
    duration = milliseconds
  }

  internal func remaining(_ now: UInt64) -> UInt64 {
    let elapsed = now >= start ? now - start : 0
    return elapsed < duration ? duration - elapsed : 0
  }
}
