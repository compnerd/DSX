// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct SignalSet: Sendable {
  private var signals = InlineArray<4, UInt64> { _ in 0 }

  internal mutating func insert(_ signal: UInt8) {
    let index = Int(signal) / UInt64.bitWidth
    let offset = Int(signal) % UInt64.bitWidth
    signals[index] |= UInt64(1) << offset
  }

  internal func contains(_ signal: CInt) -> Bool {
    guard let signal = UInt8(exactly: signal) else {
      return false
    }
    let index = Int(signal) / UInt64.bitWidth
    let offset = Int(signal) % UInt64.bitWidth
    let mask = UInt64(1) << offset
    return signals[index] & mask > 0
  }
}
