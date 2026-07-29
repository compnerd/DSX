// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(arm64)
internal import Darwin

extension DarwinDebugControl {
  internal static func step(_ thread: thread_act_t, enabled: Bool)
      throws(Debuggee.Error) {
    var state = try arm_debug_state64_t(thread)
    if enabled {
      state.__mdscr_el1 |= MDSCR_SS
    } else {
      state.__mdscr_el1 &= ~MDSCR_SS
    }
    try thread.write(state, flavor: ARM_DEBUG_STATE64)
  }
}
#endif
