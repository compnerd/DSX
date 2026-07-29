// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct BreakpointIdentifier: Equatable, Sendable {
  internal let rawValue: UInt64

  internal init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

internal enum BreakpointKind: Equatable, Sendable {
  case hardware
  case software
  case watchpoint(Debuggee.Access)
}

internal enum BreakpointLifetime: Equatable, Sendable {
  case permanent
  case untilhit
  case oneshot
}

internal struct BreakpointSite: Equatable, Sendable {
  internal let address: Debuggee.Address
  internal let size: Int
  internal let kind: BreakpointKind
  internal let lifetime: BreakpointLifetime

  internal init(address: Debuggee.Address, size: Int, kind: BreakpointKind,
                lifetime: BreakpointLifetime = .permanent) {
    self.address = address
    self.size = size
    self.kind = kind
    self.lifetime = lifetime
  }

  internal func hit(_ stop: Debuggee.Stop) -> Bool {
    guard stop.reason == .breakpoint, let address = ABI.address(stop) else {
      return false
    }
    return self.address == address
  }
}

internal enum BreakpointSlot {
  internal static func select(_ existing: Int?, available: Int?,
                              enabled: Bool) throws(Debuggee.Error) -> Int? {
    if let existing {
      return existing
    }
    guard enabled else {
      return nil
    }
    guard let available else {
      throw .breakpoint
    }
    return available
  }
}
