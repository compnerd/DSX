// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(x86_64)
internal import Darwin

extension DarwinDebugControl {
  internal static func step(_ thread: thread_act_t, enabled: Bool)
      throws(Debuggee.Error) {
    var state = try x86_thread_state64_t(thread)
    state.step(enabled: enabled)
    try state.commit(thread)
  }
}
#endif
