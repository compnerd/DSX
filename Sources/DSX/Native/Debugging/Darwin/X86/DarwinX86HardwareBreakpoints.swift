// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(x86_64)
internal import Darwin

extension HardwareBreakpoint {
  internal static let features: StaticString = "x86_64"

  internal static func advance(_ kind: BreakpointKind) -> Bool {
    // Mach clears RF when restoring general registers. Step over execution
    // comparators through the shared breakpoint lifecycle instead.
    kind == .hardware
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

extension DarwinDebugControl {
  internal func configure(_ threads: borrowing DarwinThreadList,
                          clearing: Bool = false) throws(Debuggee.Error) {
    guard clearing || !breakpoints.isEmpty else {
      return
    }
    guard let process else {
      throw .process
    }
    // The task template contains only process-wide sites. New threads inherit
    // it before executing; thread-specific sites never leak into that template.
    let task = try task(process)
    var template = try x86_debug_state64_t(breakpoints, thread: nil)
    try template.commit(task: task.handle)
    for index in 0 ..< threads.count {
      let handle = threads[index]
      let thread = try ThreadIdentifier(mach: handle)
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      var state = try x86_debug_state64_t(handle)
      guard try state.configure(breakpoints, thread: identifier) else {
        continue
      }
      try handle.write(state, flavor: x86_DEBUG_STATE64)
    }
  }

  internal mutating func breakpoint(_ process: ProcessIdentifier,
                                    site: borrowing BreakpointSite,
                                    thread: ProcessThreadIdentifier?,
                                    enabled: Bool) throws(Debuggee.Error) {
    guard self.process == process else {
      throw .process
    }
    let threads = try DarwinThreadList(process, control: self)
    if let thread {
      guard thread.process == process else {
        throw .thread
      }
      var found = false
      for index in 0 ..< threads.count {
        if try ThreadIdentifier(mach: threads[index]) == thread.thread {
          found = true
          break
        }
      }
      guard found else {
        throw .thread
      }
    }
    let previous = breakpoints
    breakpoints.update(site, thread: thread, enabled: enabled)
    do throws(Debuggee.Error) {
      try configure(threads, clearing: true)
    } catch {
      breakpoints = previous
      try? configure(threads, clearing: true)
      throw error
    }
  }

  internal func hit(_ stop: borrowing Debuggee.Stop,
                    site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    guard process == stop.thread.process else {
      return false
    }
    let location = site.address
    return switch (stop.reason, site.kind) {
    case (.trace, .hardware): stop.fault?.address == location
    case let (.watchpoint(access, address), .watchpoint(expected)):
      access == expected && address == location
    default: false
    }
  }
}

extension x86_debug_state64_t {
  internal var pending: Bool {
    __dr6 & 0x000f > 0
  }

  internal init(_ thread: thread_act_t) throws(Debuggee.Error) {
    self.init()
    try thread.read(&self, flavor: x86_DEBUG_STATE64)
  }

  @inline(never)
  internal init(_ breakpoints: borrowing ActiveBreakpoints,
                thread: ProcessThreadIdentifier?) throws(Debuggee.Error) {
    self.init()
    for index in breakpoints.indices {
      let record = breakpoints[index]
      if record.thread == nil || record.thread == thread {
        try insert(record.site)
      }
    }
  }

  internal mutating func configure(_ breakpoints: borrowing ActiveBreakpoints,
                                   thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> Bool {
    // A suspended thread can still be delivering its Mach exception. Keep
    // its comparators and status together until that hit is classified.
    guard pending == false else {
      return false
    }
    self = try x86_debug_state64_t(breakpoints, thread: thread)
    return true
  }

  internal mutating func insert(_ site: borrowing BreakpointSite)
      throws(Debuggee.Error) {
    let control = try X86BreakpointControl(site)
    for slot in 0 ..< 4 {
      if self[slot] == site.address.rawValue,
          control.matches(__dr7, slot: slot) {
        return
      }
    }
    for slot in 0 ..< 4 {
      if X86BreakpointControl.active(__dr7, slot: slot) {
        continue
      }
      self[slot] = site.address.rawValue
      return control.enable(slot, control: &__dr7)
    }
    throw .breakpoint
  }

  internal func hit(_ site: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    let control = try X86BreakpointControl(site)
    for slot in 0 ..< 4 where __dr6 & (1 << slot) > 0 {
      if self[slot] == site.address.rawValue,
          control.matches(__dr7, slot: slot) {
        return true
      }
    }
    return false
  }

  fileprivate mutating func commit(task: task_t) throws(Debuggee.Error) {
    let words = MemoryLayout.size(ofValue: self) / MemoryLayout<natural_t>.size
    let status = withUnsafeMutablePointer(to: &self) { state in
      state.withMemoryRebound(to: natural_t.self, capacity: words) {
        task_set_state(task, thread_state_flavor_t(x86_DEBUG_STATE64), $0,
                       mach_msg_type_number_t(words))
      }
    }
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
  }

  private subscript(_ slot: Int) -> UInt64 {
    get {
      switch slot {
      case 0: __dr0
      case 1: __dr1
      case 2: __dr2
      case 3: __dr3
      default: 0
      }
    }
    set {
      switch slot {
      case 0: __dr0 = newValue
      case 1: __dr1 = newValue
      case 2: __dr2 = newValue
      case 3: __dr3 = newValue
      default: break
      }
    }
  }
}
#endif
