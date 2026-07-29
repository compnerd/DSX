// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(x86_64)
internal import Darwin

extension DarwinDebugControl {
  internal static func fault(_: CInt, process _: ProcessIdentifier,
                             threads _: borrowing DarwinThreadList)
      throws(Debuggee.Error) -> Debuggee.Event? {
    nil
  }

  internal static func trap(_: CInt, event: consuming Debuggee.Event,
                            stepping _: Bool, thread: thread_act_t, code: Int64,
                            threads _: borrowing DarwinThreadList,
                            breakpoints: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> Debuggee.Event {
    guard case .stopped(let stop) = event else {
      return consume event
    }
    if code == EXC_I386_SGL {
      let state = try x86_debug_state64_t(thread)
      return try .stopped(state.trap(stop, breakpoints: breakpoints))
    }
    guard code == EXC_I386_BPT else {
      return consume event
    }
    let state = try x86_thread_state64_t(thread)
    return try .stopped(state.trap(stop, code: code))
  }
}

extension x86_debug_state64_t {
  internal func trap(_ stop: consuming Debuggee.Stop,
                     breakpoints: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> Debuggee.Stop {
    for index in breakpoints.indices {
      let record = breakpoints[index]
      guard record.thread == nil || record.thread == stop.thread,
          try hit(record.site) else {
        continue
      }
      let reason: Debuggee.StopReason = switch record.site.kind {
      case .watchpoint(let access): .watchpoint(access, record.site.address)
      default: .trace
      }
      let fault = Debuggee.Fault(address: record.site.address, domain: .mach)
      return stop.refined(reason: reason, fault: fault,
                          breakpoint: stop.breakpoint)
    }
    return stop
  }
}
#endif
