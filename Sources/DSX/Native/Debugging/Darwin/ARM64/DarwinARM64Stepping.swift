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
    // XNU caches the live debug state by object identity. With watchpoints
    // enabled, an in-place update can leave the old hardware stepping mode.
    // Replace it while the task is suspended, then restore its slots.
    try thread.write(arm_debug_state64_t(), flavor: ARM_DEBUG_STATE64)
    try thread.write(state, flavor: ARM_DEBUG_STATE64)
  }
}
#endif
