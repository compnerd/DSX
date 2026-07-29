// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) && arch(x86_64)
internal import Glibc

extension HardwareBreakpoint {
  internal static var features: StaticString {
    "x86_64"
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
    kind == .hardware
  }
}

extension BSDDebugControl {
  internal mutating func prepare(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let process, !breakpoints.isEmpty else {
      return
    }
    let threads = try process.threads
    for record in breakpoints {
      try configure(process, list: threads.span, site: record.site,
                    thread: record.thread, enabled: true)
    }
  }

  internal mutating func breakpoint(_ process: ProcessIdentifier,
                                    site: borrowing BreakpointSite,
                                    thread: ProcessThreadIdentifier?,
                                    enabled: Bool) throws(Debuggee.Error) {
    guard self.process == process else {
      throw .process
    }
    try configure(process, site: site, thread: thread, enabled: enabled)
    breakpoints.update(site, thread: thread, enabled: enabled)
  }

  internal func hit(_ stop: borrowing Debuggee.Stop,
                    site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    guard stop.reason == .trace, process == stop.thread.process else {
      return false
    }
    let thread = try identifier(stop.thread)
    let registers = try snapshot(thread)
    let status = registers[6] & DBREG_DR6_BMASK
    for slot in 0 ..< 4 where status & (1 << slot) > 0 {
      if registers[slot] == site.address.rawValue {
        return true
      }
    }
    return false
  }

  private static func configure(_ process: ProcessIdentifier,
                                site: borrowing BreakpointSite,
                                thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    let threads = try process.threads
    try configure(process, list: threads.span, site: site, thread: thread,
                  enabled: enabled)
  }

  private static func configure(_ process: ProcessIdentifier,
                                list: borrowing Span<ProcessThreadIdentifier>,
                                site: borrowing BreakpointSite,
                                thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    if let thread {
      guard thread.process == process else {
        throw .thread
      }
      return try configure(identifier(thread), site: site, enabled: enabled)
    }
    for index in 0 ..< list.count {
      try configure(identifier(list[index]), site: site, enabled: enabled)
    }
  }

  private static func configure(_ thread: pid_t, site: borrowing BreakpointSite,
                                enabled: Bool) throws(Debuggee.Error) {
    var registers = try snapshot(thread)
    let existing = slot(registers, address: site.address.rawValue)
    let available = enabled ? (0 ..< 4).first(where: { slot in
        !X86BreakpointControl.active(registers[7], slot: slot)
    }) : nil
    guard let slot = try BreakpointSlot.select(existing, available: available,
                                               enabled: enabled) else {
      return
    }
    if enabled {
      registers[slot] = site.address.rawValue
      let encoded = try X86BreakpointControl.encode(site)
      encoded.enable(slot, control: &registers[7])
    } else {
      registers[slot] = 0
      X86BreakpointControl.disable(slot, control: &registers[7])
    }
    try commit(thread, registers: &registers)
  }

  private static func slot(_ registers: borrowing InlineArray<16, UInt64>,
                           address: UInt64) -> Int? {
    (0 ..< 4).first { slot in
      X86BreakpointControl.active(registers[7], slot: slot) &&
      registers[slot] == address
    }
  }

  private static func snapshot(_ thread: pid_t) throws(Debuggee.Error)
      -> InlineArray<16, UInt64> {
    var registers = InlineArray<16, UInt64> { _ in 0 }
    try transfer(thread, registers: &registers, request: PT_GETDBREGS)
    return registers
  }

  private static func commit(_ thread: pid_t,
                             registers: inout InlineArray<16, UInt64>)
      throws(Debuggee.Error) {
    try transfer(thread, registers: &registers, request: PT_SETDBREGS)
  }

  private static func transfer(_ thread: pid_t,
                               registers: inout InlineArray<16, UInt64>,
                               request: CInt) throws(Debuggee.Error) {
    let result = withUnsafeMutablePointer(to: &registers) { registers in
      let pointer = UnsafeMutableRawPointer(registers)
        .assumingMemoryBound(to: CChar.self)
      ptrace(request, thread, pointer, 0)
    }
    guard result == 0 else {
      throw failure(errno)
    }
  }

  private static func identifier(_ thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> pid_t {
    guard thread.process.rawValue <= UInt64(pid_t.max),
        thread.thread.rawValue <= UInt64(pid_t.max) else {
      throw .thread
    }
    return pid_t(thread.thread.rawValue)
  }

  private static func failure(_ code: CInt) -> Debuggee.Error {
    switch code {
    case EINVAL, EIO: .breakpoint
    default: UnixError.debuggee(code, invalid: .thread, support: true)
    }
  }

}
#endif
