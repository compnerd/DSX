// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct Deadline {
  private let start: Duration
  private let duration: Duration

  internal init(_ duration: Duration, now: Duration) {
    start = now
    self.duration = duration
  }

  internal func remaining(at now: Duration) -> Duration {
    let start = start.attoseconds
    let now = now.attoseconds
    let duration = duration.attoseconds
    let elapsed = now >= start ? now - start : 0
    return Duration(attoseconds: elapsed < duration ? duration - elapsed : 0)
  }
}
