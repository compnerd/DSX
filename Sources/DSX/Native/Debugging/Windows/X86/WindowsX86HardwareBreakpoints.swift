// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(i386) || arch(x86_64))
internal import WinSDK

extension HardwareBreakpoint {
  internal static var features: StaticString {
    ABI.machine
  }

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

extension WindowsDebugControl {
  internal static func configure(_ site: borrowing BreakpointSite,
                                 enabled: Bool, handle: HANDLE)
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
    var context =
        try WindowsContext.snapshot(handle, flags: CONTEXT_DEBUG_REGISTERS)
    let existing =
        slot(site.address.rawValue, control: control, context: context)
    let available = enabled ? (0 ..< 4).first(where: { candidate in
      !X86BreakpointControl.active(context.Dr7, slot: candidate)
    }) : nil
    guard let slot = try BreakpointSlot.select(existing, available: available,
                                               enabled: enabled) else {
      return
    }
    if enabled {
      let raw = site.address.rawValue
      let value = X86BreakpointControl.Word(truncatingIfNeeded: raw)
      address(slot, value: value, context: &context)
      control.enable(slot, control: &context.Dr7)
    } else {
      X86BreakpointControl.disable(slot, control: &context.Dr7)
      address(slot, value: 0, context: &context)
    }
    try WindowsContext.commit(context, to: handle)
  }

  internal func hit(_ stop: borrowing Debuggee.Stop,
                    site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    let requested = site.address
    guard stop.reason == .trace,
        stop.thread.thread.rawValue <= UInt64(DWORD.max),
        let handle = threads[DWORD(stop.thread.thread.rawValue)]?.handle else {
      return false
    }
    let context =
        try WindowsContext.snapshot(handle, flags: CONTEXT_DEBUG_REGISTERS)
    let control = try X86BreakpointControl(site)
    for slot in 0 ..< 4 where context.Dr6 & (1 << slot) != 0 {
      let address = WindowsDebugControl.address(slot, context: context)
      if address == requested.rawValue,
          control.matches(context.Dr7, slot: slot) {
        return true
      }
    }
    return false
  }

  internal static func exception(_ code: DWORD, hardware _: Bool)
      -> Debuggee.StopReason {
    exception(code)
  }

  private static func slot(_ address: UInt64, control: X86BreakpointControl,
                           context: borrowing CONTEXT) -> Int? {
    for slot in 0 ..< 4 where control.matches(context.Dr7, slot: slot) {
      if WindowsDebugControl.address(slot, context: context) == address {
        return slot
      }
    }
    return nil
  }

  internal static func address(_ slot: Int,
                               context: borrowing CONTEXT) -> UInt64 {
    switch slot {
    case 0: UInt64(context.Dr0)
    case 1: UInt64(context.Dr1)
    case 2: UInt64(context.Dr2)
    case 3: UInt64(context.Dr3)
    default: 0
    }
  }

  private static func address(_ slot: Int, value: X86BreakpointControl.Word,
                              context: inout CONTEXT) {
    switch slot {
    case 0: context.Dr0 = value
    case 1: context.Dr1 = value
    case 2: context.Dr2 = value
    case 3: context.Dr3 = value
    default: break
    }
  }
}
#endif
