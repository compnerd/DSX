// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(arm64)
internal import Darwin

private let kARMWatchpointNumberValid: UInt32 = 1 << 17
private let kARMWatchpointNumberShift: UInt32 = 18
private let kARMWatchpointNumberMask: UInt32 = 0x3f

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
                            stepping: Bool, thread _: thread_act_t,
                            code _: Int64, threads: borrowing DarwinThreadList,
                            breakpoints: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> Debuggee.Event {
    let signal = UnixWaitStatus(status).signal
    guard signal == SIGBUS || signal == SIGTRAP,
        case .stopped(let stop) = event else {
      return consume event
    }
    let result = try DarwinDebugControl.trap(stop, specific: stepping,
                                             threads: threads,
                                             breakpoints: breakpoints)
    guard let stop = result else {
      return consume event
    }
    return .stopped(stop)
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
    try DarwinDebugControl.configure(process, site: site, thread: thread,
                                     enabled: enabled)
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
      try DarwinDebugControl.configure(process, threads: threads,
                                       site: record.site, thread: record.thread,
                                       enabled: true)
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

  internal static func site(_ exception: borrowing arm_exception_state64_t,
                            thread: thread_act_t,
                            identifier: ProcessThreadIdentifier,
                            breakpoints: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> BreakpointSite? {
    let code = exception.__esr >> 26
    let watchpoint = code == ESR_EC_WATCHPT_MATCH_EL0 ||
        code == ESR_EC_WATCHPT_MATCH_EL1
    if watchpoint {
      if exception.__esr & kARMWatchpointNumberValid != 0 {
        let number = exception.__esr >> kARMWatchpointNumberShift &
            kARMWatchpointNumberMask
        let slot = Int(number)
        let count = try DarwinDebugControl.capacity(.watchpoint)
        guard slot < count else {
          return nil
        }
        let state = try arm_debug_state64_t(thread)
        let location = state.address(slot, bank: .watchpoint)
        let control = state.settings(slot, bank: .watchpoint)
        guard let index = try owner(location, control: control,
                                    thread: identifier,
                                    breakpoints: breakpoints) else {
          return nil
        }
        return breakpoints[index].site
      }
      guard let index =
          breakpoints.nearest(exception.__far, thread: identifier) else {
        return nil
      }
      return breakpoints[index].site
    }
    let breakpoint = code == ESR_EC_BKPT_REG_MATCH_EL0 ||
        code == ESR_EC_BKPT_REG_MATCH_EL1
    guard breakpoint else {
      return nil
    }
    let program = try arm_thread_state64_t(thread).__pc
    return breakpoints.first { record in
      guard case .hardware = record.site.kind else {
        return false
      }
      let selected = record.thread == nil || record.thread == identifier
      return selected && record.site.address.rawValue == program
    }?.site
  }

  private static func owner(_ location: UInt64, control: UInt64,
                            thread: ProcessThreadIdentifier,
                            breakpoints: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> ActiveBreakpoints.Index? {
    var selected: ActiveBreakpoints.Index?
    for index in breakpoints.indices {
      let record = breakpoints[index]
      guard case .watchpoint = record.site.kind,
          record.thread == nil || record.thread == thread else {
        continue
      }
      let controls = try ARM64BreakpointControl.partition(record.site)
      let matches = controls.first.matches(address: location,
                                           control: control) ||
          controls.second?.matches(address: location, control: control) == true
      guard matches else {
        continue
      }
      if let selected, breakpoints[selected].site != record.site {
        return nil
      }
      selected = index
    }
    return selected
  }

  private static func configure(_ process: ProcessIdentifier,
                                site: borrowing BreakpointSite,
                                thread: ProcessThreadIdentifier?, enabled: Bool)
      throws(Debuggee.Error) {
    let threads = try DarwinThreadList(process)
    try configure(process, threads: threads, site: site, thread: thread,
                  enabled: enabled)
  }

  private static func configure(_ process: ProcessIdentifier,
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
        if try identity(candidate) == thread.thread {
          return try configure(candidate, site: site, enabled: enabled)
        }
      }
      throw .thread
    }
    let task = try DarwinTask(process)
    for index in 0 ..< threads.count {
      let handle = index == 0 ? task.handle : nil
      try configure(threads[index], task: handle, site: site, enabled: enabled)
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
      settings(candidate, bank: bank) & 1 == 0
    }) : nil
    guard let index = try BreakpointSlot.select(existing, available: available,
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
