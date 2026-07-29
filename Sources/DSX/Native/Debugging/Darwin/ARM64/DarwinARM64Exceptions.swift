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
      let state = try arm_exception_state64_t(thread)
      let code = UInt64(state.__esr >> 26)
      switch code {
      case ESR_EC_IABORT_EL0, ESR_EC_IABORT_EL1,
           ESR_EC_DABORT_EL0, ESR_EC_DABORT_EL1:
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
      let exception = try arm_exception_state64_t(thread)
      let code = UInt64(exception.__esr >> 26)
      let watchpoint = code == ESR_EC_WATCHPT_MATCH_EL0 ||
          code == ESR_EC_WATCHPT_MATCH_EL1
      let breakpoint = code == ESR_EC_BKPT_REG_MATCH_EL0 ||
          code == ESR_EC_BKPT_REG_MATCH_EL1
      let trace = code == ESR_EC_SW_STEP_DEBUG_EL0 ||
          code == ESR_EC_SW_STEP_DEBUG_EL1
      let software = code == ESR_EC_BRK_AARCH64
      guard watchpoint || breakpoint || trace || software else {
        continue
      }
      let identifier = try identity(thread)
      let pair = ProcessThreadIdentifier(process: stop.thread.process,
                                         thread: identifier)
      let address =
          try watchpoint ? exception.__far : arm_thread_state64_t(thread).__pc
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


}
#endif
