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
      case ESR_EC_IABORT_EL0, ESR_EC_IABORT_EL1, ESR_EC_DABORT_EL0,
          ESR_EC_DABORT_EL1:
        let identifier = try ThreadIdentifier(mach: thread)
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

  internal static func trap(_ stop: consuming Debuggee.Stop,
                            thread: thread_act_t) throws(Debuggee.Error)
      -> Debuggee.Stop {
    let exception = try arm_exception_state64_t(thread)
    let code = UInt64(exception.__esr >> 26)
    let reason: Debuggee.StopReason? = switch code {
    case ESR_EC_BRK_AARCH64: .breakpoint
    case ESR_EC_BKPT_REG_MATCH_EL0, ESR_EC_BKPT_REG_MATCH_EL1,
        ESR_EC_SW_STEP_DEBUG_EL0, ESR_EC_SW_STEP_DEBUG_EL1: .trace
    default: nil
    }
    guard let reason else { return stop }
    let address = try arm_thread_state64_t(thread).__pc
    let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: address),
                               code: UInt64(exception.__esr), domain: .mach)
    return stop.refined(reason: reason, fault: fault,
                         breakpoint: stop.breakpoint)
  }

}
#endif
