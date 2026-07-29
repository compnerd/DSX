// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(arm64)
internal import Darwin

extension HardwareBreakpoint {
  internal static let features: StaticString = "aarch64-mask,aarch64-bas"

  internal static var capacity: Int? {
    get throws(Debuggee.Error) {
      try DarwinDebugControl.capacity(.watchpoint)
    }
  }

  internal static func supports(_ kind: BreakpointKind) -> Bool {
    HardwareBreakpoint.supports(kind, available: true)
  }

  internal static func advance(_ kind: BreakpointKind) -> Bool {
    kind == .hardware
  }
}

extension DarwinDebugControl {
  internal static func fault(_ status: CInt, process: ProcessIdentifier,
                             threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) -> Debuggee.Event? {
    let signal = UnixWaitStatus(status).signal
    guard signal == SIGBUS || signal == SIGSEGV,
        let fault =
            try DarwinDebugControl.fault(process, threads: threads) else {
      return nil
    }
    return .stopped(fault)
  }

  internal static func trap(_ status: CInt, event: consuming Debuggee.Event,
                            stepping _: Bool, thread: thread_act_t,
                            code: Int64, threads _: borrowing DarwinThreadList,
                            breakpoints: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> Debuggee.Event {
    let signal = UnixWaitStatus(status).signal
    guard signal == SIGBUS || signal == SIGTRAP,
        case .stopped(let stop) = event else {
      return consume event
    }
    // Mach supplies the accessed address for a data breakpoint. The thread's
    // ESR can describe an earlier exception, so it is not authoritative here.
    if code == EXC_ARM_DA_DEBUG, let fault = stop.fault {
      let reason: Debuggee.StopReason =
          if let index = breakpoints.nearest(fault.address.rawValue,
                                             thread: stop.thread),
              case .watchpoint(let access) = breakpoints[index].site.kind {
            .watchpoint(access, breakpoints[index].site.address)
          } else {
            .exception(UInt64(EXC_BREAKPOINT))
          }
      return .stopped(stop.refined(reason: reason, fault: fault,
                                   breakpoint: stop.breakpoint))
    }
    return try .stopped(DarwinDebugControl.trap(stop, thread: thread))
  }

  internal mutating func breakpoint(_ process: ProcessIdentifier,
                                    site: borrowing BreakpointSite,
                                    thread: ProcessThreadIdentifier?,
                                    enabled: Bool) throws(Debuggee.Error) {
    guard self.process == process else {
      throw .process
    }
    if enabled {
      breakpoints.update(site, thread: thread, enabled: true)
    }
    try configure(process, site: site, thread: thread, enabled: enabled)
    if enabled == false {
      breakpoints.update(site, thread: thread, enabled: false)
    }
  }

  internal mutating func configure(_ threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    guard let process, !breakpoints.isEmpty else {
      return
    }
    for record in breakpoints {
      try configure(process, threads: threads,
                    site: record.site, thread: record.thread, enabled: true)
    }
  }

  internal func hit(_ stop: borrowing Debuggee.Stop,
                    site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    guard process == stop.thread.process else {
      return false
    }
    switch (stop.reason, site.kind) {
    case (.trace, .hardware):
      return stop.fault?.address == site.address
    case (.watchpoint(let access, let address), .watchpoint(let expected)):
      guard access == expected else {
        return false
      }
      return address == site.address
    default:
      return false
    }
  }

  private func configure(_ process: ProcessIdentifier,
                         site: borrowing BreakpointSite,
                         thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    let threads = try DarwinThreadList(process, control: self)
    try configure(process, threads: threads, site: site, thread: thread,
                  enabled: enabled)
  }

  private func configure(_ process: ProcessIdentifier,
                         threads: borrowing DarwinThreadList,
                         site: borrowing BreakpointSite,
                         thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    if let thread {
      guard thread.process == process else {
        throw .thread
      }
      for index in 0 ..< threads.count {
        let candidate = threads[index]
        if try ThreadIdentifier(mach: candidate) == thread.thread {
          return try DarwinDebugControl.configure(candidate, site: site,
                                                  enabled: enabled)
        }
      }
      throw .thread
    }
    let task = try task(process)
    for index in 0 ..< threads.count {
      let handle = index == 0 ? task.handle : nil
      try DarwinDebugControl.configure(threads[index], task: handle, site: site,
                                       enabled: enabled)
    }
  }

  private static func configure(_ thread: thread_act_t,
                                task: mach_port_name_t? = nil,
                                site: borrowing BreakpointSite, enabled: Bool)
      throws(Debuggee.Error) {
    guard let controls = try? ARM64BreakpointControl.partition(site),
        let bank = try? ARM64BreakpointBank(site.kind) else {
      if enabled {
        throw .breakpoint
      }
      return
    }
    var state = try arm_debug_state64_t(thread)
    let capacity = try capacity(bank)
    var changed = try state.configure(controls.first, bank: bank,
                                      capacity: capacity, enabled: enabled)
    if let second = controls.second {
      let update = try state.configure(second, bank: bank, capacity: capacity,
                                       enabled: enabled)
      changed = changed || update
    }
    guard changed else {
      return
    }
    try thread.write(state, flavor: ARM_DEBUG_STATE64)
    if let task {
      let words =
          MemoryLayout<arm_debug_state64_t>.size / MemoryLayout<natural_t>.size
      let count = mach_msg_type_number_t(words)
      let status = withUnsafeMutablePointer(to: &state) { state in
        state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
          task_set_state(task, thread_state_flavor_t(ARM_DEBUG_STATE64), $0,
                         count)
        }
      }
      guard status == KERN_SUCCESS else {
        throw Debuggee.Error(mach: status, invalid: .process)
      }
    }
  }

  internal static func capacity(_ bank: ARM64BreakpointBank)
      throws(Debuggee.Error) -> Int {
    var count: UInt32 = 0
    var size = MemoryLayout.size(ofValue: count)
    let name =
        bank.breakpoint ? "hw.optional.breakpoint" : "hw.optional.watchpoint"
    let status = name.withCString { name in
      sysctlbyname(name, &count, &size, nil, 0)
    }
    guard status == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    return min(Int(count), 16)
  }

}

extension arm_debug_state64_t {
  fileprivate mutating func configure(_ encoded: ARM64BreakpointControl,
                                      bank: ARM64BreakpointBank, capacity: Int,
                                      enabled: Bool) throws(Debuggee.Error)
      -> Bool {
    let existing = slot(encoded, bank: bank, capacity: capacity)
    let available = enabled ? (0 ..< capacity).first(where: { candidate in
      settings(candidate, bank: bank) & ARM_DBG_CR_ENABLE_MASK == 0
    }) : nil
    guard let index = try DSX::slot(existing: existing, available: available,
                                    enabled: enabled) else {
      return false
    }
    address(index, bank: bank, value: enabled ? encoded.address : 0)
    settings(index, bank: bank, value: enabled ? encoded.control : 0)
    return true
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
      return withUnsafeBytes(of: __bvr) { bytes in
        bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
      }
    }
    return withUnsafeBytes(of: __wvr) { bytes in
      bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
    }
  }

  private mutating func address(_ slot: Int, bank: ARM64BreakpointBank,
                                value: UInt64) {
    if bank.breakpoint {
      withUnsafeMutableBytes(of: &__bvr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    } else {
      withUnsafeMutableBytes(of: &__wvr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    }
  }

  fileprivate func settings(_ slot: Int, bank: ARM64BreakpointBank) -> UInt64 {
    if bank.breakpoint {
      return withUnsafeBytes(of: __bcr) { bytes in
        bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
      }
    }
    return withUnsafeBytes(of: __wcr) { bytes in
      bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
    }
  }

  private mutating func settings(_ slot: Int, bank: ARM64BreakpointBank,
                                 value: UInt64) {
    if bank.breakpoint {
      withUnsafeMutableBytes(of: &__bcr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    } else {
      withUnsafeMutableBytes(of: &__wcr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    }
  }
}
#endif
