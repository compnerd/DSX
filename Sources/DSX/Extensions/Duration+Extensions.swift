// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Duration {
  internal enum RoundingRule {
    case up
    case down
  }

  /// Returns a count of units clamped to the unsigned range.
  internal func rounded(to unit: Duration, rule: RoundingRule) -> UInt64 {
    let value = attoseconds
    let divisor = unit.attoseconds
    precondition(divisor > 0)
    guard value > 0 else {
      return 0
    }
    switch rule {
    case .up: return UInt64(clamping: (value - 1) / divisor + 1)
    case .down: return UInt64(clamping: value / divisor)
    }
  }
}
