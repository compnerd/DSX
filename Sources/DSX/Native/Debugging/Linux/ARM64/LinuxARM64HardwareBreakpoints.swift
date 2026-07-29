// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension HardwareBreakpoint {
  internal static let features: StaticString = "aarch64-bas"

  internal static var capacity: Int? {
    get throws(Debuggee.Error) {
      nil
    }
  }

  internal static func supports(_ kind: BreakpointKind) -> Bool {
    HardwareBreakpoint.supports(kind, available: true)
  }

  internal static func advance(_ kind: BreakpointKind) -> Bool {
    kind == .hardware
  }
}

private struct LinuxARM64DebugRegister {
  fileprivate var address: UInt64
  fileprivate var control: UInt32
  private var padding: UInt32

  fileprivate init() {
    address = 0
    control = 0
    padding = 0
  }
}

private struct LinuxARM64DebugRegisters {
  private var info: UInt32
  private var padding: UInt32
  private var registers: InlineArray<16, LinuxARM64DebugRegister>

  fileprivate var count: Int {
    Int(info & 0xff)
  }

  private init() {
    info = 0
    padding = 0
    registers = InlineArray<16, LinuxARM64DebugRegister> { _ in
      LinuxARM64DebugRegister()
    }
  }
}

private let kMinimumDebugArchitecture: UInt32 = 0x06

extension LinuxDebugControl {
  internal func watchpoints(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Int {
    try LinuxARM64DebugRegisters(thread(process), note: NT_ARM_HW_WATCH).count
  }

  internal func hit(_ stop: borrowing Debuggee.Stop,
                    site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    let stopped = stop.thread
    guard stop.reason == .trace,
        stopped.thread.rawValue <= UInt64(pid_t.max) else {
      return false
    }
    let thread = pid_t(stopped.thread.rawValue)
    let mask: UInt64 = if case .watchpoint = site.kind {
      LinuxARM64AddressMask(thread).data
    } else {
      0
    }
    let expected = try LinuxDebugControl.adjust(site, mask: mask)
    if let fault = stop.fault {
      switch expected.kind {
      case .hardware:
        return fault.address == expected.address
      case .watchpoint:
        let encoded = try ARM64BreakpointControl(expected)
        return encoded.contains(fault.address.rawValue & ~mask)
      case .software:
        return false
      }
    }
    return false
  }

  internal static func configure(_ thread: pid_t,
                                 site: borrowing BreakpointSite, enabled: Bool)
      throws(Debuggee.Error) {
    let mask: UInt64 = if case .watchpoint = site.kind {
      LinuxARM64AddressMask(thread).data
    } else {
      0
    }
    guard let adjusted = try? adjust(site, mask: mask),
        let encoded = try? ARM64BreakpointControl(adjusted),
        let bank = try? ARM64BreakpointBank(adjusted.kind) else {
      if enabled {
        throw .breakpoint
      }
      return
    }
    let note = bank.breakpoint ? NT_ARM_HW_BREAK : NT_ARM_HW_WATCH
    var state = try LinuxARM64DebugRegisters(thread, note: note)
    guard try state.configure(encoded, enabled: enabled) else {
      return
    }
    try state.commit(thread, note: note)
  }

  internal static func adjust(_ site: borrowing BreakpointSite, mask: UInt64)
      throws(Debuggee.Error) -> BreakpointSite {
    guard case .watchpoint = site.kind else {
      return BreakpointSite(address: site.address, size: site.size,
                            kind: site.kind, lifetime: site.lifetime)
    }
    switch site.size {
    case 1, 2, 4, 8:
      break
    default:
      throw .breakpoint
    }
    let address = Debuggee.Address(rawValue: site.address.rawValue & ~mask)
    let offset = address.rawValue & 0x7
    guard offset > 0 else {
      return BreakpointSite(address: address, size: site.size, kind: site.kind,
                            lifetime: site.lifetime)
    }
    let requested = UInt64(site.size)
    guard requested <= 8 - offset else {
      throw .breakpoint
    }
    let extent = offset + requested
    let size = switch extent {
    case ...2: 2
    case ...4: 4
    default: 8
    }
    let aligned = Debuggee.Address(rawValue: address.rawValue & ~0x7)
    return BreakpointSite(address: aligned, size: size, kind: site.kind,
                          lifetime: site.lifetime)
  }
}

extension LinuxARM64DebugRegisters {
  fileprivate mutating func configure(_ encoded: ARM64BreakpointControl,
                                      enabled: Bool) throws(Debuggee.Error)
      -> Bool {
    let existing = slot(encoded.address, control: UInt32(encoded.control))
    if enabled, existing == nil, occupied(encoded.address) {
      throw .breakpoint
    }
    let available = enabled ? available : nil
    guard let index = try BreakpointSlot.select(existing, available: available,
                                                enabled: enabled) else {
      return false
    }
    if enabled {
      registers[index].address = encoded.address
      registers[index].control = UInt32(encoded.control)
    } else {
      registers[index].address = 0
      registers[index].control = 0
    }
    return true
  }

  private func slot(_ address: UInt64, control: UInt32) -> Int? {
    for index in 0 ..< count {
      let register = registers[index]
      if register.address == address, register.control == control {
        return index
      }
    }
    return nil
  }

  private var available: Int? {
    for index in 0 ..< count {
      if registers[index].control & 1 == 0 {
        return index
      }
    }
    return nil
  }

  private func occupied(_ address: UInt64) -> Bool {
    for index in 0 ..< count {
      let register = registers[index]
      if register.control & 1 > 0, register.address == address {
        return true
      }
    }
    return false
  }
}

extension LinuxARM64DebugRegisters {
  fileprivate init(_ thread: pid_t, note: Int) throws(Debuggee.Error) {
    self.init()
    let length =
        try withUnsafeMutableBytes(of: &self, { bytes throws(Debuggee.Error) in
      try bytes.transfer(PTRACE_GETREGSET, note: note, thread: thread,
                         complete: false,
                         failure: Debuggee.Error.init(breakpoint:))
    })
    guard length >= 8 else {
      throw .breakpoint
    }
    guard info >> 8 & 0xff >= kMinimumDebugArchitecture else {
      throw .unsupported
    }
    let stride = MemoryLayout<LinuxARM64DebugRegister>.stride
    let available = (length - 8) / stride
    let count = min(Int(info & 0xff), available, 16)
    guard count > 0 else {
      throw .unsupported
    }
    info = info & ~0xff | UInt32(count)
  }

  fileprivate mutating func commit(_ thread: pid_t, note: Int)
      throws(Debuggee.Error) {
    let count = count
    info = 0
    padding = 0
    let length = 8 + count * MemoryLayout<LinuxARM64DebugRegister>.stride
    _ = try withUnsafeMutableBytes(of: &self, { bytes throws(Debuggee.Error) in
      let buffer = UnsafeMutableRawBufferPointer(rebasing: bytes.prefix(length))
      return try buffer.transfer(PTRACE_SETREGSET, note: note, thread: thread,
                                 complete: false,
                                 failure: Debuggee.Error.init(breakpoint:))
    })
  }
}
#endif
