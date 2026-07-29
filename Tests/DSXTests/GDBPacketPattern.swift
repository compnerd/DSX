// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

@testable internal import DSX

internal let kWatchpoints: String =
    if HardwareBreakpoint.features.utf8CodeUnitCount > 0 {
      ";SupportedWatchpointTypes=\(HardwareBreakpoint.features)"
    } else {
      ""
    }

internal struct GDBPacketPattern: Sendable {
  internal let prefix: StaticString
  internal let exact: Bool

  internal init(_ prefix: StaticString, exact: Bool = true) {
    self.prefix = prefix
    self.exact = exact
  }

  internal var count: Int {
    prefix.utf8CodeUnitCount
  }

  internal func matches(_ packet: borrowing Span<UInt8>) -> Bool {
    prefix.withUTF8Buffer { prefix in
      guard packet.count >= prefix.count else {
        return false
      }
      for index in 0 ..< prefix.count {
        guard packet[index] == prefix[index] else {
          return false
        }
      }
      return exact ? packet.count == prefix.count : true
    }
  }
}
