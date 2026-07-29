// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(arm64)
internal import Darwin

extension HardwareBreakpoint {
  internal static var features: StaticString {
    "aarch64-mask,aarch64-bas"
  }

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
  internal func step(_ selection: Debuggee.Thread.Selection,
                     process: ProcessIdentifier,
                     threads: borrowing DarwinThreadList,
                     request: inout CInt) throws(Debuggee.Error)
      -> ProcessThreadIdentifier? {
    request = kPTContinue
    if case .thread(let thread) = selection {
      return thread
    }
    guard threads.count > 0 else {
      return nil
    }
    let thread = try identity(threads[0])
    return ProcessThreadIdentifier(process: process, thread: thread)
  }

  internal mutating func step(_ actions: borrowing Debuggee.Continuations,
                              process: ProcessIdentifier,
                              threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    try finish(threads)
    for index in 0 ..< threads.count {
      let candidate = threads[index]
      let thread = try identity(candidate)
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      let action =
          try Debuggee.Continuation.Plan.resolve(identifier, actions: actions)
      guard action?.operation == .step else {
        continue
      }
      try DarwinDebugControl.step(candidate, enabled: true)
      steps.append(identifier)
    }
  }

  internal mutating func finish(_ threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    var pending = steps.count
    while pending > 0 {
      pending -= 1
      let identifier = steps[pending]
      for index in 0 ..< threads.count {
        let candidate = threads[index]
        guard try identity(candidate) == identifier.thread else {
          continue
        }
        try DarwinDebugControl.step(candidate, enabled: false)
        break
      }
      steps.remove(at: pending)
    }
  }

  internal static func fault(_ status: CInt, process: ProcessIdentifier,
                             threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) -> Debuggee.Event? {
    let signal = UnixWaitStatus.signal(status)
    guard signal == SIGBUS || signal == SIGSEGV,
        let fault = try DarwinDebugControl.fault(process,
                                                 threads: threads) else {
      return nil
    }
    return .stopped(fault)
  }

  internal static func trap(_ status: CInt, event: consuming Debuggee.Event,
                            stepping: Bool, threads: borrowing DarwinThreadList,
                            breakpoints: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> Debuggee.Event {
    let signal = UnixWaitStatus.signal(status)
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
    try DarwinDebugControl.configure(process, site: site, thread: thread,
                                     enabled: enabled)
    breakpoints.update(site, thread: thread, enabled: enabled)
  }

  internal mutating func prepare(_ actions: borrowing Debuggee.Continuations,
                                 threads: borrowing DarwinThreadList)
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
    let watchpoint = code == kARMExceptionWatchpointLower ||
        code == kARMExceptionWatchpointCurrent
    if watchpoint {
      if exception.__esr & kARMWatchpointNumberValid != 0 {
        let number = exception.__esr >> kARMWatchpointNumberShift &
            kARMWatchpointNumberMask
        let slot = Int(number)
        let count = try DarwinDebugControl.capacity(.watchpoint)
        guard slot < count else {
          return nil
        }
        let state = try snapshot(thread)
        let location = address(slot, bank: .watchpoint, state: state)
        let control = settings(slot, bank: .watchpoint, state: state)
        guard let index = try owner(location, control: control,
                                    thread: identifier,
                                    breakpoints: breakpoints) else {
          return nil
        }
        return breakpoints[index].site
      }
      guard let index = breakpoints.nearest(exception.__far,
                                            thread: identifier) else {
        return nil
      }
      return breakpoints[index].site
    }
    let breakpoint = code == kARMExceptionBreakpointLower ||
        code == kARMExceptionBreakpointCurrent
    guard breakpoint else {
      return nil
    }
    let program = try pc(thread)
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
    let controls = try ARM64BreakpointControl.partition(site)
    let bank = try ARM64BreakpointBank(site.kind)
    var state = try snapshot(thread)
    let bytes = MemoryLayout<arm_debug_state64_t>.size
    let words = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(words)
    let capacity = try capacity(bank)
    var changed = try configure(controls.first, bank: bank, capacity: capacity,
                                enabled: enabled, state: &state)
    if let second = controls.second {
      let update = try configure(second, bank: bank, capacity: capacity,
                                 enabled: enabled, state: &state)
      changed = changed || update
    }
    guard changed else {
      return
    }
    count = mach_msg_type_number_t(words)
    var status = withUnsafeMutablePointer(to: &state) { state in
      state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_set_state(thread, thread_state_flavor_t(ARM_DEBUG_STATE64), $0,
                         count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    if let task {
      count = mach_msg_type_number_t(words)
      status = withUnsafeMutablePointer(to: &state) { state in
        state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
          task_set_state(task, thread_state_flavor_t(ARM_DEBUG_STATE64), $0,
                         count)
        }
      }
      guard status == KERN_SUCCESS else {
        throw DarwinError.debuggee(status, invalid: .process)
      }
    }
  }

  private static func configure(_ encoded: ARM64BreakpointControl,
                                bank: ARM64BreakpointBank, capacity: Int,
                                enabled: Bool, state: inout arm_debug_state64_t)
      throws(Debuggee.Error) -> Bool {
    let existing = slot(encoded.address, control: encoded.control, bank: bank,
                        capacity: capacity, state: state)
    let available = enabled ? (0 ..< capacity).first(where: { candidate in
      settings(candidate, bank: bank, state: state) & 1 == 0
    }) : nil
    guard let index = try BreakpointSlot.select(existing, available: available,
                                                enabled: enabled) else {
      return false
    }
    address(index, bank: bank, value: enabled ? encoded.address : 0,
            state: &state)
    settings(index, bank: bank, value: enabled ? encoded.control : 0,
             state: &state)
    return true
  }

  private static func snapshot(_ thread: thread_act_t) throws(Debuggee.Error)
      -> arm_debug_state64_t {
    var state = arm_debug_state64_t()
    let bytes = MemoryLayout<arm_debug_state64_t>.size
    let words = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(words)
    let status = withUnsafeMutablePointer(to: &state) { state in
      state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_get_state(thread, thread_state_flavor_t(ARM_DEBUG_STATE64), $0,
                         &count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    return state
  }

  private static func step(_ thread: thread_act_t, enabled: Bool)
      throws(Debuggee.Error) {
    var state = arm_debug_state64_t()
    let words =
        MemoryLayout<arm_debug_state64_t>.size / MemoryLayout<UInt32>.size
    var count = mach_msg_type_number_t(words)
    var status = withUnsafeMutablePointer(to: &state) { state in
      state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_get_state(thread, thread_state_flavor_t(ARM_DEBUG_STATE64), $0,
                         &count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    if enabled {
      state.__mdscr_el1 |= kARMDebugSingleStep
    } else {
      state.__mdscr_el1 &= ~kARMDebugSingleStep
    }
    count = mach_msg_type_number_t(words)
    status = withUnsafeMutablePointer(to: &state) { state in
      state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_set_state(thread, thread_state_flavor_t(ARM_DEBUG_STATE64), $0,
                         count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
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
      throw DarwinError.debuggee(errno, invalid: .thread)
    }
    return min(Int(count), 16)
  }

  private static func slot(_ value: UInt64, control expected: UInt64,
                           bank: ARM64BreakpointBank, capacity: Int,
                           state: borrowing arm_debug_state64_t) -> Int? {
    for slot in 0 ..< capacity {
      if address(slot, bank: bank, state: state) == value,
          settings(slot, bank: bank, state: state) == expected {
        return slot
      }
    }
    return nil
  }

  private static func address(_ slot: Int, bank: ARM64BreakpointBank,
                              state: borrowing arm_debug_state64_t) -> UInt64 {
    if bank.breakpoint {
      return withUnsafeBytes(of: state.__bvr) { bytes in
        bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
      }
    }
    return withUnsafeBytes(of: state.__wvr) { bytes in
      bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
    }
  }

  private static func address(_ slot: Int, bank: ARM64BreakpointBank,
                              value: UInt64, state: inout arm_debug_state64_t) {
    if bank.breakpoint {
      withUnsafeMutableBytes(of: &state.__bvr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    } else {
      withUnsafeMutableBytes(of: &state.__wvr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    }
  }

  private static func settings(_ slot: Int, bank: ARM64BreakpointBank,
                               state: borrowing arm_debug_state64_t) -> UInt64 {
    if bank.breakpoint {
      return withUnsafeBytes(of: state.__bcr) { bytes in
        bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
      }
    }
    return withUnsafeBytes(of: state.__wcr) { bytes in
      bytes.loadUnaligned(fromByteOffset: slot * 8, as: UInt64.self)
    }
  }

  private static func settings(_ slot: Int, bank: ARM64BreakpointBank,
                               value: UInt64,
                               state: inout arm_debug_state64_t) {
    if bank.breakpoint {
      withUnsafeMutableBytes(of: &state.__bcr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    } else {
      withUnsafeMutableBytes(of: &state.__wcr) { bytes in
        bytes.storeBytes(of: value, toByteOffset: slot * 8, as: UInt64.self)
      }
    }
  }

  private static func pc(_ thread: thread_act_t) throws(Debuggee.Error)
      -> UInt64 {
    var state = arm_thread_state64_t()
    let bytes = MemoryLayout<arm_thread_state64_t>.size
    let words = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(words)
    let status = withUnsafeMutablePointer(to: &state) { state in
      state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_get_state(thread, thread_state_flavor_t(ARM_THREAD_STATE64), $0,
                         &count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    return state.__pc
  }

  private static func exception(_ thread: thread_act_t) throws(Debuggee.Error)
      -> arm_exception_state64_t {
    var state = arm_exception_state64_t()
    let bytes = MemoryLayout<arm_exception_state64_t>.size
    let words = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(words)
    let status = withUnsafeMutablePointer(to: &state) { state in
      state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_get_state(thread, thread_state_flavor_t(ARM_EXCEPTION_STATE64),
                         $0, &count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    return state
  }

}
#endif
