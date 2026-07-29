// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(arm64)
internal import WinSDK

extension HardwareBreakpoint {
  internal static let features: StaticString = "aarch64-bas"

  internal static func advance(_ kind: BreakpointKind) -> Bool {
    supports(kind)
  }

  internal static var capacity: Int? {
    get throws(Debuggee.Error) {
      nil
    }
  }

  internal static func supports(_ kind: BreakpointKind) -> Bool {
    switch kind {
    case .watchpoint: true
    case .hardware, .software: false
    }
  }
}

extension WindowsDebugThread {
  internal func watchpoints() throws(Debuggee.Error) -> Int {
    var original = try CONTEXT(handle, flags: CONTEXT_ALL)
    let location = Debuggee.Address(rawValue: original.Sp & ~7)
    let site =
        BreakpointSite(address: location, size: 1, kind: .watchpoint(.write))
    let encoded = try ARM64BreakpointControl(site)
    original.ContextFlags = CONTEXT_DEBUG_REGISTERS
    var context = original
    for index in 0 ..< ARM64_MAX_WATCHPOINTS {
      context.address(index, bank: .watchpoint, value: encoded.address)
      context.settings(index, bank: .watchpoint, value: encoded.control)
    }
    // CONTEXT's array size is an upper bound. Windows can silently discard
    // unavailable slots. Probe while the debug event holds every thread, then
    // restore the original bank before returning (including read failures).
    try context.commit(to: handle)
    let observed = Result { () throws(Debuggee.Error) in
      try CONTEXT(handle, flags: CONTEXT_DEBUG_REGISTERS)
    }
    try original.commit(to: handle)
    let bank = try observed.get()
    var count = 0
    for index in 0 ..< ARM64_MAX_WATCHPOINTS {
      let value = bank.address(index, bank: .watchpoint)
      let control = bank.settings(index, bank: .watchpoint)
      if encoded.matches(address: value, control: control) {
        count += 1
      }
    }
    return count
  }

  internal func configure(_ site: borrowing BreakpointSite, enabled: Bool)
      throws(Debuggee.Error) {
    guard let encoded = try? ARM64BreakpointControl(site),
        let bank = try? ARM64BreakpointBank(site.kind) else {
      if enabled {
        throw .breakpoint
      }
      return
    }
    var context = try CONTEXT(handle, flags: CONTEXT_DEBUG_REGISTERS)
    let capacity =
        bank.breakpoint ? ARM64_MAX_BREAKPOINTS : ARM64_MAX_WATCHPOINTS
    guard let index = try context.configure(encoded, bank: bank,
                                            capacity: capacity,
                                            enabled: enabled) else {
      return
    }
    try context.commit(to: handle)
    if enabled {
      let observed = try CONTEXT(handle, flags: CONTEXT_DEBUG_REGISTERS)
      let value = observed.address(index, bank: bank)
      let control = observed.settings(index, bank: bank)
      guard encoded.matches(address: value, control: control) else {
        throw .breakpoint
      }
    }
  }
}

extension WindowsDebugControl {
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
      let encoded = try ARM64BreakpointControl(site)
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
}

extension EXCEPTION_RECORD {
  internal var hardware: Bool {
    ExceptionCode == EXCEPTION_BREAKPOINT && NumberParameters >= 2
  }
}

extension CONTEXT {
  fileprivate mutating func configure(_ encoded: ARM64BreakpointControl,
                                      bank: ARM64BreakpointBank, capacity: Int,
                                      enabled: Bool)
      throws(Debuggee.Error) -> Int? {
    let existing = slot(encoded, bank: bank, capacity: capacity)
    let available = enabled ? (0 ..< capacity).first(where: { candidate in
        settings(candidate, bank: bank) & 1 == 0
    }) : nil
    guard let index = try BreakpointSlot.select(existing, available: available,
                                                enabled: enabled) else {
      return nil
    }
    if enabled {
      address(index, bank: bank, value: encoded.address)
      settings(index, bank: bank, value: encoded.control)
    } else {
      address(index, bank: bank, value: 0)
      settings(index, bank: bank, value: 0)
    }
    return index
  }

  private func slot(_ expected: ARM64BreakpointControl,
                    bank: ARM64BreakpointBank, capacity: Int) -> Int? {
    for slot in 0 ..< capacity {
      let address = address(slot, bank: bank)
      let control = settings(slot, bank: bank)
      let matches = bank.breakpoint
          ? expected.address == address && expected.control == control
          : expected.matches(address: address, control: control)
      if matches {
        return slot
      }
    }
    return nil
  }

  fileprivate func address(_ slot: Int, bank: ARM64BreakpointBank) -> UInt64 {
    if bank.breakpoint {
      return withUnsafeBytes(of: Bvr) { bytes in
        bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
      }
    }
    return withUnsafeBytes(of: Wvr) { bytes in
      bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
    }
  }

  fileprivate mutating func address(_ slot: Int, bank: ARM64BreakpointBank,
                                    value: UInt64) {
    if bank.breakpoint {
      withUnsafeMutableBytes(of: &Bvr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    } else {
      withUnsafeMutableBytes(of: &Wvr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    }
  }

  fileprivate func settings(_ slot: Int, bank: ARM64BreakpointBank) -> UInt64 {
    if bank.breakpoint {
      return withUnsafeBytes(of: Bcr) { bytes in
        UInt64(bytes.loadUnaligned(fromByteOffset: slot * 4, as: UInt32.self))
      }
    }
    return withUnsafeBytes(of: Wcr) { bytes in
      UInt64(bytes.loadUnaligned(fromByteOffset: slot * 4, as: UInt32.self))
    }
  }

  fileprivate mutating func settings(_ slot: Int, bank: ARM64BreakpointBank,
                                     value: UInt64) {
    if bank.breakpoint {
      withUnsafeMutableBytes(of: &Bcr) { bytes in
        bytes.storeBytes(of: UInt32(value), toByteOffset: slot * 4,
                         as: UInt32.self)
      }
    } else {
      withUnsafeMutableBytes(of: &Wcr) { bytes in
        bytes.storeBytes(of: UInt32(value), toByteOffset: slot * 4,
                         as: UInt32.self)
      }
    }
  }
}
#endif
