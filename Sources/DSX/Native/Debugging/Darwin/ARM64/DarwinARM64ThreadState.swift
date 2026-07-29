// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(arm64)
internal import Darwin

extension arm_thread_state64_t {
  internal init(_ thread: thread_act_t) throws(Debuggee.Error) {
    self.init()
    try thread.read(&self, flavor: ARM_THREAD_STATE64)
  }
}

extension arm_exception_state64_t {
  internal init(_ thread: thread_act_t) throws(Debuggee.Error) {
    self.init()
    try thread.read(&self, flavor: ARM_EXCEPTION_STATE64)
  }
}

extension arm_debug_state64_t {
  internal init(_ thread: thread_act_t) throws(Debuggee.Error) {
    self.init()
    try thread.read(&self, flavor: ARM_DEBUG_STATE64)
  }
}
#endif
