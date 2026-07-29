// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(arm64)
internal import WinSDK

extension HardwareBreakpoint {
  internal static var features: StaticString {
    "aarch64-bas"
  }

  internal static func advance(_ kind: BreakpointKind) -> Bool {
    supports(kind)
  }

  internal static var capacity: Int? {
    get throws(Debuggee.Error) {
      ARM64_MAX_WATCHPOINTS
    }
  }

  internal static func supports(_ kind: BreakpointKind) -> Bool {
    switch kind {
    case .watchpoint: true
    case .hardware, .software: false
    }
  }
}

extension WindowsDebugControl {
  internal static func configure(_ site: borrowing BreakpointSite,
                                 enabled: Bool, handle: HANDLE)
      throws(Debuggee.Error) {
    let encoded = try ARM64BreakpointControl.encode(site)
    let bank = try ARM64BreakpointBank(site.kind)
    var context =
        try WindowsContext.snapshot(handle, flags: CONTEXT_DEBUG_REGISTERS)
    let capacity =
        bank.breakpoint ? ARM64_MAX_BREAKPOINTS : ARM64_MAX_WATCHPOINTS
    let existing = slot(encoded.address, control: encoded.control, bank: bank,
                        capacity: capacity, context: context)
    let available = enabled ? (0 ..< capacity).first(where: { candidate in
        settings(candidate, bank: bank, context: context) & 1 == 0
    }) : nil
    guard let index = try BreakpointSlot.select(existing, available: available,
                                                enabled: enabled) else {
      return
    }
    if enabled {
      address(index, bank: bank, value: encoded.address, context: &context)
      settings(index, bank: bank, value: encoded.control, context: &context)
    } else {
      address(index, bank: bank, value: 0, context: &context)
      settings(index, bank: bank, value: 0, context: &context)
    }
    try WindowsContext.commit(context, to: handle)
  }

  internal func hit(_ stop: borrowing Debuggee.Stop,
                    site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    let kind = site.kind
    guard stop.reason == .trace, let fault = stop.fault,
        fault.code == UInt64(EXCEPTION_BREAKPOINT),
        let data = fault.data, data.count >= 2 else {
      return false
    }
    switch kind {
    case .hardware:
      return fault.address == site.address
    case .watchpoint:
      let encoded = try ARM64BreakpointControl.encode(site)
      if encoded.contains(fault.address.rawValue) {
        return true
      }
      var matches = false
      var count = 0
      for record in breakpoints {
        guard case .watchpoint = record.site.kind else {
          continue
        }
        if let thread = record.thread {
          guard thread == stop.thread else {
            continue
          }
        }
        count += 1
        if record.site == site {
          matches = true
        }
      }
      return count == 1 && matches
    case .software:
      return false
    }
  }

  internal static func exception(_ code: DWORD, hardware: Bool)
      -> Debuggee.StopReason {
    if hardware {
      .trace
    } else {
      exception(code)
    }
  }

  private static func slot(_ value: UInt64, control expected: UInt64,
                           bank: ARM64BreakpointBank, capacity: Int,
                           context: borrowing CONTEXT) -> Int? {
    for slot in 0 ..< capacity {
      if address(slot, bank: bank, context: context) == value,
          settings(slot, bank: bank, context: context) == expected {
        return slot
      }
    }
    return nil
  }

  private static func address(_ slot: Int, bank: ARM64BreakpointBank,
                              context: borrowing CONTEXT) -> UInt64 {
    if bank.breakpoint {
      return withUnsafeBytes(of: context.Bvr) { bytes in
        bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
      }
    }
    return withUnsafeBytes(of: context.Wvr) { bytes in
      bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
    }
  }

  private static func address(_ slot: Int, bank: ARM64BreakpointBank,
                              value: UInt64, context: inout CONTEXT) {
    if bank.breakpoint {
      withUnsafeMutableBytes(of: &context.Bvr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    } else {
      withUnsafeMutableBytes(of: &context.Wvr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    }
  }

  private static func settings(_ slot: Int, bank: ARM64BreakpointBank,
                               context: borrowing CONTEXT) -> UInt64 {
    if bank.breakpoint {
      return withUnsafeBytes(of: context.Bcr) { bytes in
        UInt64(bytes.loadUnaligned(fromByteOffset: slot * 4, as: UInt32.self))
      }
    }
    return withUnsafeBytes(of: context.Wcr) { bytes in
      UInt64(bytes.loadUnaligned(fromByteOffset: slot * 4, as: UInt32.self))
    }
  }

  private static func settings(_ slot: Int, bank: ARM64BreakpointBank,
                               value: UInt64, context: inout CONTEXT) {
    if bank.breakpoint {
      withUnsafeMutableBytes(of: &context.Bcr) { bytes in
        bytes.storeBytes(of: UInt32(value), toByteOffset: slot * 4,
                         as: UInt32.self)
      }
    } else {
      withUnsafeMutableBytes(of: &context.Wcr) { bytes in
        bytes.storeBytes(of: UInt32(value), toByteOffset: slot * 4,
                         as: UInt32.self)
      }
    }
  }
}
#endif
