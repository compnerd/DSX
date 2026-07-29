// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(arm64)
internal enum ARM64BreakpointBank: Sendable {
  case breakpoint
  case watchpoint

  internal var breakpoint: Bool {
    if case .breakpoint = self { true } else { false }
  }

  internal init(_ kind: BreakpointKind) throws(Debuggee.Error) {
    switch kind {
    case .hardware: self = .breakpoint
    case .watchpoint: self = .watchpoint
    case .software: throw .breakpoint
    }
  }
}

internal struct ARM64BreakpointControl: Sendable {
  internal let address: UInt64
  internal let control: UInt64

  internal init(address: UInt64, control: UInt64) {
    self.address = address
    self.control = control
  }

  internal init(_ site: borrowing BreakpointSite) throws(Debuggee.Error) {
    let controls = try ARM64BreakpointControl.partition(site)
    guard controls.second == nil else {
      throw .breakpoint
    }
    self = controls.first
  }

  internal static func partition(_ site: borrowing BreakpointSite)
      throws(Debuggee.Error) -> (first: ARM64BreakpointControl,
                                 second: ARM64BreakpointControl?) {
    switch site.kind {
    case .hardware:
      guard site.size == 4, site.address.rawValue & 0x3 == 0 else {
        throw .breakpoint
      }
      // DBGBCR<n>_EL1: enabled, EL0, all four instruction bytes.
      let E: UInt64 = 1
      let PMC: UInt64 = 0b10
      let BAS: UInt64 = 0x0f
      let control = E | PMC << 1 | BAS << 5
      let encoded = ARM64BreakpointControl(address: site.address.rawValue,
                                           control: control)
      return (first: encoded, second: nil)
    case .watchpoint(let access):
      guard site.size > 0 else {
        throw .breakpoint
      }
      let size = UInt64(site.size)
      let address = site.address.rawValue
      if let encoded =
          try ARM64BreakpointControl(address, size: size, access: access) {
        return (first: encoded, second: nil)
      }
      let aligned = try alignment(size)
      let base = address & ~(aligned - 1)
      let (boundary, overflow) = base.addingReportingOverflow(aligned)
      if overflow {
        throw .breakpoint
      }
      let first = boundary - address
      let second = size - first
      let parts =
          try (ARM64BreakpointControl(address, size: first, access: access),
               ARM64BreakpointControl(boundary, size: second, access: access))
      guard let low = parts.0, let high = parts.1 else {
        throw .breakpoint
      }
      return (first: low, second: high)
    case .software:
      throw .breakpoint
    }
  }

  internal func matches(address: UInt64, control: UInt64) -> Bool {
    // Compare DBGWCR<n>_EL1 installation fields, not privilege policy.
    let E: UInt64 = 1
    let LSC: UInt64 = 0b11
    let BAS: UInt64 = 0xff
    let MASK: UInt64 = 0x1f
    let mask = E | LSC << 3 | BAS << 5 | MASK << 24
    return self.address == address && self.control & mask == control & mask
  }

  internal func contains(_ address: UInt64) -> Bool {
    let MASK = Int(control >> 24 & 0x1f)
    if MASK > 0 {
      return self.address >> MASK == address >> MASK
    }
    guard address >= self.address else {
      return false
    }
    let offset = address - self.address
    guard offset < 8 else {
      return false
    }
    let bit = UInt64(1) << offset
    let BAS = control >> 5 & 0xff
    return BAS & bit != 0
  }

  private init?(_ address: UInt64, size: UInt64, access: Debuggee.Access)
      throws(Debuggee.Error) {
    let aligned = try ARM64BreakpointControl.alignment(size)
    let base = address & ~(aligned - 1)
    let (end, overflow) = address.addingReportingOverflow(size)
    let (limit, exceeded) = base.addingReportingOverflow(aligned)
    if overflow || exceeded || limit < end {
      return nil
    }
    // DBGWCR<n>_EL1: enabled, EL0, selected load/store accesses.
    let E: UInt64 = 1
    let PAC: UInt64 = 0b10
    let LSC: UInt64 = switch access {
    case .read: 0b01
    case .write: 0b10
    case .readwrite: 0b11
    case .execute: throw .breakpoint
    }
    let control: UInt64
    if aligned > 8 {
      let MASK = UInt64(aligned.trailingZeroBitCount)
      let BAS: UInt64 = 0xff
      control = E | PAC << 1 | LSC << 3 | BAS << 5 | MASK << 24
    } else {
      let offset = address & 0x7
      let BAS = ((UInt64(1) << size) - 1) << offset
      control = E | PAC << 1 | LSC << 3 | BAS << 5
    }
    self.init(address: base, control: control)
  }

  private static func alignment(_ requested: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    let requested = max(requested, 8)
    guard requested <= UInt64(1) << 31 else {
      throw .breakpoint
    }
    if requested.nonzeroBitCount == 1 {
      return requested
    }
    return UInt64(1) << (UInt64.bitWidth - requested.leadingZeroBitCount)
  }
}
#endif
