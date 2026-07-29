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
                            breakpoints _: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> Debuggee.Event {
    guard code == EXC_I386_BPT, case .stopped(let stop) = event else {
      return consume event
    }
    let state = try x86_thread_state64_t(thread)
    return try .stopped(state.trap(stop, code: code))
  }
}
#endif
