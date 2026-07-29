// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && (arch(i386) || arch(x86_64))
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension HardwareBreakpoint {
  internal static var features: StaticString {
    ABI.machine
  }

  internal static var capacity: Int? {
    get throws(Debuggee.Error) {
      4
    }
  }

  internal static func supports(_ kind: BreakpointKind) -> Bool {
    HardwareBreakpoint.supports(kind, available: true)
  }

  internal static func advance(_ kind: BreakpointKind) -> Bool {
    switch kind {
    case .hardware: true
    case .software, .watchpoint: false
    }
  }
}

private let kDebugSlotCount = 4
private let kDebugStatusRegister = 6
private let kDebugControlRegister = 7

extension LinuxDebugControl {
  internal func watchpoints(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Int {
    guard self.process == process else {
      throw .process
    }
    return 4
  }

  internal func hit(_ stop: borrowing Debuggee.Stop,
                    site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    guard stop.reason == .trace,
        stop.thread.thread.rawValue <= UInt64(pid_t.max) else {
      return false
    }
    let thread = pid_t(stop.thread.thread.rawValue)
    let status =
        try LinuxDebugControl.read(thread, register: kDebugStatusRegister)
    let control = try X86BreakpointControl(site)
    let configuration =
        try LinuxDebugControl.read(thread, register: kDebugControlRegister)
    for slot in 0 ..< kDebugSlotCount where status & (1 << slot) != 0 {
      let address = try LinuxDebugControl.read(thread, register: slot)
      if UInt64(address) == site.address.rawValue,
          control.matches(configuration, slot: slot) {
        return true
      }
    }
    return false
  }

  internal static func configure(_ thread: pid_t,
                                 site: borrowing BreakpointSite, enabled: Bool)
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
    var status = try read(thread, register: kDebugControlRegister)
    let existing =
        try slot(thread, address: site.address.rawValue, control: control,
                 status: status)
    let slots = 0 ..< kDebugSlotCount
    let available = enabled ? slots.first(where: { candidate in
        !X86BreakpointControl.active(status, slot: candidate)
    }) : nil
    guard let index = try BreakpointSlot.select(existing, available: available,
                                                enabled: enabled) else {
      return
    }
    if enabled {
      let hits = try X86BreakpointControl
        .acknowledge(read(thread, register: kDebugStatusRegister), slot: index)
      try write(thread, register: kDebugStatusRegister, value: hits)
      let raw = site.address.rawValue
      let address = X86BreakpointControl.Word(truncatingIfNeeded: raw)
      try write(thread, register: index, value: address)
      control.enable(index, control: &status)
    } else {
      X86BreakpointControl.disable(index, control: &status)
      try write(thread, register: kDebugControlRegister, value: status)
      return try write(thread, register: index, value: 0)
    }
    try write(thread, register: kDebugControlRegister, value: status)
  }

  private static func slot(_ thread: pid_t, address: UInt64,
                           control: X86BreakpointControl,
                           status: X86BreakpointControl.Word)
      throws(Debuggee.Error) -> Int? {
    for slot in 0 ..< kDebugSlotCount
        where control.matches(status, slot: slot) {
      if try UInt64(read(thread, register: slot)) == address {
        return slot
      }
    }
    return nil
  }

  private static func read(_ thread: pid_t, register: Int)
      throws(Debuggee.Error) -> X86BreakpointControl.Word {
    errno = 0
    let width = MemoryLayout<X86BreakpointControl.Word>.size
    let offset = kUserDebugRegisterOffset + register * width
    let address = UnsafeMutableRawPointer(bitPattern: offset)
    let value = ptrace(PTRACE_PEEKUSER, thread, address, nil)
    if value == -1, errno > 0 {
      throw UnixError.breakpoint(errno)
    }
    return X86BreakpointControl.Word(truncatingIfNeeded: value)
  }

  private static func write(_ thread: pid_t, register: Int,
                            value: X86BreakpointControl.Word)
      throws(Debuggee.Error) {
    let width = MemoryLayout<X86BreakpointControl.Word>.size
    let offset = kUserDebugRegisterOffset + register * width
    let address = UnsafeMutableRawPointer(bitPattern: offset)
    let data = UnsafeMutableRawPointer(bitPattern: UInt(value))
    guard ptrace(PTRACE_POKEUSER, thread, address, data) == 0 else {
      throw UnixError.breakpoint(errno)
    }
  }
}
#endif
