// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(x86_64)
internal import Darwin

extension x86_thread_state64_t {
  internal mutating func step(enabled: Bool) {
    if enabled {
      __rflags |= UInt64(EFL_TF)
    } else {
      __rflags &= ~UInt64(EFL_TF)
    }
  }

  internal func trap(_ stop: Debuggee.Stop, code: Int64) throws(Debuggee.Error)
      -> Debuggee.Stop {
    guard code == EXC_I386_BPT else {
      return stop
    }
    // INT3 reports the instruction after the trap. The shared breakpoint
    // table rewinds the PC only when this is one of our installed sites.
    guard __rip > 0 else {
      throw .register
    }
    let address = Debuggee.Address(rawValue: __rip - 1)
    let fault = Debuggee.Fault(address: address, domain: .mach)
    return stop.refined(reason: .breakpoint, fault: fault,
                        breakpoint: stop.breakpoint)
  }

  internal init(_ thread: thread_act_t) throws(Debuggee.Error) {
    self.init()
    try thread.read(&self, flavor: x86_THREAD_STATE64)
  }

  internal func commit(_ thread: thread_act_t) throws(Debuggee.Error) {
    try thread.write(self, flavor: x86_THREAD_STATE64)
  }
}
#endif
