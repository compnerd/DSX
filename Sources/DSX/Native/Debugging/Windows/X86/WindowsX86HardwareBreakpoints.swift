// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(i386) || arch(x86_64))
internal import WinSDK

extension HardwareBreakpoint {
  internal static let features: StaticString = ABI.machine

  internal static func advance(_ kind: BreakpointKind) -> Bool {
    supports(kind)
  }

  internal static var capacity: Int? {
    get throws(Debuggee.Error) {
      4
    }
  }

  internal static func supports(_ kind: BreakpointKind) -> Bool {
    HardwareBreakpoint.supports(kind, available: true)
  }
}

extension WindowsDebugThread {
  internal func watchpoints() throws(Debuggee.Error) -> Int {
    4
  }

  internal func configure(_ site: borrowing BreakpointSite, enabled: Bool)
      throws(Debuggee.Error) {
    guard let control = try? X86BreakpointControl(site) else {
      if enabled {
        throw .breakpoint
      }
      return
    }
#if arch(i386)
    if site.address.rawValue > UInt64(UInt32.max) {
      if enabled {
        throw .breakpoint
      }
      return
    }
#endif
    var context = try CONTEXT(handle, flags: CONTEXT_DEBUG_REGISTERS)
    guard try context.configure(control, address: site.address.rawValue,
                                enabled: enabled) else {
      return
    }
    try context.commit(to: handle)
  }
}

extension WindowsDebugControl {
  internal func hit(_ stop: borrowing Debuggee.Stop,
                    site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    guard stop.reason == .trace,
        stop.thread.thread.rawValue <= UInt64(DWORD.max),
        let handle = threads[DWORD(stop.thread.thread.rawValue)]?.handle else {
      return false
    }
    let context = try CONTEXT(handle, flags: CONTEXT_DEBUG_REGISTERS)
    return try context.hit(site)
  }

  internal static func exception(_ code: DWORD, hardware _: Bool)
      -> Debuggee.StopReason {
    exception(code)
  }
}

extension EXCEPTION_RECORD {
  internal var hardware: Bool {
    // x86 debug-register traps are single-step exceptions. Parameters on an
    // INT3 exception do not encode the ARM64 watchpoint address.
    false
  }
}

extension CONTEXT {
  fileprivate func hit(_ site: borrowing BreakpointSite)
      throws(Debuggee.Error) -> Bool {
    let requested = site.address
    let control = try X86BreakpointControl(site)
    for slot in 0 ..< 4 where Dr6 & (1 << slot) != 0 {
      let address = UInt64(self[slot])
      if address == requested.rawValue,
          control.matches(Dr7, slot: slot) {
        return true
      }
    }
    return false
  }

  @inline(__always)
  fileprivate mutating func configure(_ control: X86BreakpointControl,
                                      address: UInt64, enabled: Bool)
      throws(Debuggee.Error) -> Bool {
    let existing = slot(address, control: control)
    let available = enabled ? (0 ..< 4).first(where: { candidate in
      X86BreakpointControl.active(Dr7, slot: candidate) == false
    }) : nil
    guard let slot = try BreakpointSlot.select(existing, available: available,
                                               enabled: enabled) else {
      return false
    }
    if enabled {
      let value = X86BreakpointControl.Word(truncatingIfNeeded: address)
      self[slot] = value
      control.enable(slot, control: &Dr7)
    } else {
      X86BreakpointControl.disable(slot, control: &Dr7)
      self[slot] = 0
    }
    return true
  }

  private func slot(_ address: UInt64, control: X86BreakpointControl) -> Int? {
    for slot in 0 ..< 4 where control.matches(Dr7, slot: slot) {
      if UInt64(self[slot]) == address {
        return slot
      }
    }
    return nil
  }

  private subscript(_ slot: Int) -> X86BreakpointControl.Word {
    get {
      switch slot {
      case 0: Dr0
      case 1: Dr1
      case 2: Dr2
      case 3: Dr3
      default: 0
      }
    }
    set {
      switch slot {
      case 0: Dr0 = newValue
      case 1: Dr1 = newValue
      case 2: Dr2 = newValue
      case 3: Dr3 = newValue
      default: break
      }
    }
  }
}
#endif
