// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func next(state: borrowing GDBRemoteSessionState)
      throws(Debuggee.Error) -> Debuggee.Event? {
    while let event = try next(global: state.nonstop == false) {
      if case .started = event {
        guard state.events else {
          try discard(event)
          continue
        }
      }
      if case .terminated(let thread, _) = event {
        let option = state.options.contains(thread, option: 0x02)
        let requested = state.events || option
        guard requested else {
          try discard(event)
          continue
        }
      }
      if case .executed(let thread) = event, state.compatibility == .gdb,
          state.negotiation.enabled.contains(.execute) == false {
        DSX.log("continuing past unreported execution", level: .trace,
                channel: .process)
        try ignore(thread)
        continue
      }
      if case .stopped(let stop) = event, stop.reason == .vforkdone {
        if state.negotiation.enabled.contains(.vfork) {
          return event
        }
        DSX.log("continuing past unreported vfork completion", level: .trace,
                channel: .process)
        try ignore(stop.thread)
        continue
      }
      guard case .forked(let fork) = event else {
        return event
      }
      if state.negotiation.enabled.contains(fork.vfork ? .vfork : .fork) {
        return event
      }
      DSX.log("continuing past unreported fork", level: .trace,
              channel: .process)
      try ignore(fork)
    }
    return nil
  }
}
