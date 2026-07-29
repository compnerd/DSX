// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(arm64)
internal import Darwin

extension DarwinDebugControl {
  internal static func fault(_ process: ProcessIdentifier,
                             threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) -> Debuggee.Stop? {
    for index in 0 ..< threads.count {
      let thread = threads[index]
      let state = try exception(thread)
      let code = UInt64(state.__esr >> 26)
      switch code {
      case kARMExceptionInstructionAbortLower,
           kARMExceptionInstructionAbortCurrent,
           kARMExceptionDataAbortLower, kARMExceptionDataAbortCurrent:
        let identifier = try identity(thread)
        let pair = ProcessThreadIdentifier(process: process, thread: identifier)
        let address = Debuggee.Address(rawValue: state.__far)
        let fault = Debuggee.Fault(address: address, code: UInt64(state.__esr),
                                   domain: .mach)
        return Debuggee.Stop(thread: pair, reason: .exception(0x91),
                             fault: fault)
      default:
        continue
      }
    }
    return nil
  }

  internal static func trap(_ stop: borrowing Debuggee.Stop, specific: Bool,
                            threads: borrowing DarwinThreadList,
                            breakpoints: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> Debuggee.Stop? {
    var selected: Debuggee.Stop?
    for index in 0 ..< threads.count {
      let thread = threads[index]
      if specific {
        guard try identity(thread) == stop.thread.thread else {
          continue
        }
      }
      let exception = try exception(thread)
      let code = UInt64(exception.__esr >> 26)
      let watchpoint = code == kARMExceptionWatchpointLower ||
          code == kARMExceptionWatchpointCurrent
      let breakpoint = code == kARMExceptionBreakpointLower ||
          code == kARMExceptionBreakpointCurrent
      let trace = code == kARMExceptionStepLower ||
          code == kARMExceptionStepCurrent
      let software = code == kARMExceptionSoftwareBreakpoint
      guard watchpoint || breakpoint || trace || software else {
        continue
      }
      let identifier = try identity(thread)
      let pair = ProcessThreadIdentifier(process: stop.thread.process,
                                         thread: identifier)
      let address =
          if watchpoint { exception.__far } else { try program(thread) }
      let site = try DarwinDebugControl.site(exception, thread: thread,
                                             identifier: pair,
                                             breakpoints: breakpoints)
      let reason: Debuggee.StopReason = switch (software, watchpoint, site) {
      case (true, _, _): .breakpoint
      case (false, true, .some(let site)):
        switch site.kind {
        case .watchpoint(let access): .watchpoint(access, site.address)
        default: stop.reason
        }
      default: stop.reason
      }
      let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: address),
                                 code: UInt64(exception.__esr), domain: .mach)
      let candidate = Debuggee.Stop(thread: pair, reason: reason,
                                    core: stop.core, fault: fault,
                                    breakpoint: stop.breakpoint,
                                    child: stop.child, snapshot: stop.snapshot,
                                    chance: stop.chance)
      if watchpoint {
        return candidate
      }
      if selected == nil || software {
        selected = candidate
      }
    }
    return selected
  }

  private static func exception(_ thread: thread_t) throws(Debuggee.Error)
      -> arm_exception_state64_t {
    var state = arm_exception_state64_t()
    let bytes = MemoryLayout<arm_exception_state64_t>.size
    let size = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(size)
    let status = withUnsafeMutablePointer(to: &state) { state in
      state.withMemoryRebound(to: natural_t.self,
                              capacity: Int(count)) { state in
        thread_get_state(thread, thread_state_flavor_t(ARM_EXCEPTION_STATE64),
                         state, &count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    return state
  }

  private static func program(_ thread: thread_t) throws(Debuggee.Error)
      -> UInt64 {
    var state = arm_thread_state64_t()
    let bytes = MemoryLayout<arm_thread_state64_t>.size
    let size = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(size)
    let status = withUnsafeMutablePointer(to: &state) { state in
      state.withMemoryRebound(to: natural_t.self,
                              capacity: Int(count)) { state in
        thread_get_state(thread, thread_state_flavor_t(ARM_THREAD_STATE64),
                         state, &count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    return state.__pc
  }
}
#endif
