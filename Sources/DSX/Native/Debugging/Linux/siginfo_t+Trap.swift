// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

extension siginfo_t {
  internal func trap(pc: UInt64, fallback: Debuggee.StopReason,
                     stepping: Bool = false) throws(Debuggee.Error)
      -> (address: UInt64, reason: Debuggee.StopReason) {
    if si_code == SI_KERNEL || si_code == TRAP_BRKPT {
      return try (ABI.breakpoint(pc), .breakpoint)
    }
    let address = if si_code == TRAP_HWBKPT {
      withUnsafePointer(to: self) { UInt64(dsx_siginfo_address($0)) }
    } else {
      pc
    }
    return switch si_code {
    case ...0: (address, stepping ? .trace : .signal(SIGTRAP))
    case TRAP_TRACE: (address, .trace)
    default: (address, fallback)
    }
  }
}
#endif
