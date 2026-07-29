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

  private static let kEnable: UInt64 = 1 << 0
  private static let kPrivilege: UInt64 = 2 << 1
  private static let kLoad: UInt64 = 1 << 3
  private static let kStore: UInt64 = 2 << 3
  private static let kAddress: UInt64 = 5
  private static let kByteMask: UInt64 = 0xff << kAddress
  private static let kRange: UInt64 = 0x1f << 24
  private static let kWatchMask: UInt64 =
      kEnable | kLoad | kStore | kByteMask | kRange

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
      let control = kEnable | kPrivilege | UInt64(0xf) << kAddress
      let encoded = ARM64BreakpointControl(address: site.address.rawValue,
                                           control: control)
      return (first: encoded, second: nil)
    case .watchpoint(let access):
      guard site.size > 0 else {
        throw .breakpoint
      }
      let size = UInt64(site.size)
      let address = site.address.rawValue
      if let encoded = try watch(address, size: size, access: access) {
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
      let parts = try (watch(address, size: first, access: access),
                       watch(boundary, size: second, access: access))
      guard let low = parts.0, let high = parts.1 else {
        throw .breakpoint
      }
      return (first: low, second: high)
    case .software:
      throw .breakpoint
    }
  }

  internal func matches(address: UInt64, control: UInt64) -> Bool {
    let mask = ARM64BreakpointControl.kWatchMask
    return self.address == address && self.control & mask == control & mask
  }

  internal func contains(_ address: UInt64) -> Bool {
    let mask = Int(control >> 24 & 0x1f)
    if mask > 0 {
      return self.address >> mask == address >> mask
    }
    guard address >= self.address else {
      return false
    }
    let offset = address - self.address
    guard offset < 8 else {
      return false
    }
    let bit = UInt64(1) << offset
    return control >> ARM64BreakpointControl.kAddress & bit != 0
  }

  private static func watch(_ address: UInt64, size: UInt64,
                            access: Debuggee.Access)
      throws(Debuggee.Error) -> ARM64BreakpointControl? {
    let aligned = try alignment(size)
    let base = address & ~(aligned - 1)
    let (end, overflow) = address.addingReportingOverflow(size)
    let (limit, exceeded) = base.addingReportingOverflow(aligned)
    if overflow || exceeded || limit < end {
      return nil
    }
    let access: UInt64 = switch access {
    case .read: kLoad
    case .write: kStore
    case .readwrite: kLoad | kStore
    case .execute: throw .breakpoint
    }
    let control: UInt64
    if aligned > 8 {
      let mask = UInt64(aligned.trailingZeroBitCount) << 24
      control = kEnable | kPrivilege | access | kByteMask | mask
    } else {
      let offset = address & 0x7
      let bytes = ((UInt64(1) << size) - 1) << offset
      control = kEnable | kPrivilege | access | bytes << kAddress
    }
    return ARM64BreakpointControl(address: base, control: control)
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
