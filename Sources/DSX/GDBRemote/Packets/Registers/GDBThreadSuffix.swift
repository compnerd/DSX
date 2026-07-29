// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal typealias GDBThreadSuffixResult =
    (range: Range<Int>, thread: ProcessThreadIdentifier?)

internal enum GDBThreadSuffix {
  internal static func parse(_ payload: borrowing Span<UInt8>, enabled: Bool,
                             debuggee: borrowing Debuggee)
      throws(GDBHandlerError) -> GDBThreadSuffixResult {
    guard enabled else {
      return (0 ..< payload.count, nil)
    }
    var suffix = GDBPacketReader(payload.extracting(0...))
    let range: Range<Int>
    do {
      range = try suffix.field(UInt8(ascii: ";"))
    } catch .malformed {
      return (0 ..< payload.count, nil)
    }
    var end = payload.count
    if payload[end - 1] == UInt8(ascii: ";") {
      end -= 1
    }
    var reader =
        GDBPacketReader(payload.extracting(range.upperBound + 1 ..< end))
    guard reader.consume("thread:") else {
      throw .malformed
    }
    let selection =
        try GDBThreadIdentifier.parse(reader.remaining(), debuggee: debuggee)
    guard case .thread(let thread) = selection else {
      throw .debuggee(.thread)
    }
    return (range, thread)
  }
}
