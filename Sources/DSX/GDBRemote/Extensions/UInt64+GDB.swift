// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension UInt64 {
  internal var digits: Int {
    Swift.max(1, (UInt64.bitWidth - leadingZeroBitCount + 3) / 4)
  }

  internal init(decimal payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    self = try reader.decimal()
    guard reader.empty else {
      throw .malformed
    }
  }
}
