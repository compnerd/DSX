// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

extension Debuggee.Event {
  internal func fault(_ thread: pid_t)
      throws(Debuggee.Error) -> Debuggee.Event {
    guard case .stopped(let stop) = self,
        case .signal(let signal) = stop.reason else {
      return self
    }
    let information = try siginfo_t(thread)
    guard let raw = information.address(for: signal) else {
      return self
    }
    let address = Debuggee.Address(rawValue: raw)
    let code = UInt64(information.si_code)
    let fault = Debuggee.Fault(address: address, code: code, domain: .posix)
    return .stopped(stop.refined(reason: stop.reason, fault: fault,
                                 breakpoint: stop.breakpoint))
  }

  internal func trap(_ thread: pid_t, stepping: Bool) throws(Debuggee.Error)
      -> Debuggee.Event {
    guard case .stopped(let stop) = self else {
      return self
    }
    let registers = try LinuxGeneralRegisters(thread)
    let information = try siginfo_t(thread)
    let detail = try information.trap(pc: UInt64(registers.pc),
                                      fallback: stop.reason, stepping: stepping)
    let address = Debuggee.Address(rawValue: detail.address)
    let fault = Debuggee.Fault(address: address, domain: .posix)
    return .stopped(stop.refined(reason: detail.reason, fault: fault,
                                 breakpoint: stop.breakpoint))
  }
}
#endif
