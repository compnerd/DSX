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
  internal init(_ thread: pid_t,
                failure: (CInt) -> Debuggee.Error = Debuggee.Error.init(unix:))
      throws(Debuggee.Error) {
    self.init()
    let status = withUnsafeMutablePointer(to: &self) { information in
      ptrace(PTRACE_GETSIGINFO, thread, nil,
             UnsafeMutableRawPointer(information))
    }
    guard status == 0 else {
      throw failure(errno)
    }
  }

  internal func generated(by process: pid_t) -> Bool {
    guard si_code == SI_USER || si_code == SI_TKILL else {
      return false
    }
    return withUnsafePointer(to: self) { information in
      dsx_siginfo_sender(information) == process
    }
  }

  internal func address(_ signal: CInt) -> Bool {
    let standard = si_code >= SEGV_MAPERR && si_code <= SEGV_PKUERR
    return switch signal {
    case SIGBUS: si_code >= BUS_ADRALN && si_code <= BUS_MCEERR_AO
    case SIGSEGV:
      standard || si_code == SEGV_MTEAERR || si_code == SEGV_MTESERR ||
          si_code == SEGV_CPERR || si_code == SI_KERNEL
    default: false
    }
  }

  internal func trap(program: UInt64, fallback: Debuggee.StopReason,
                     stepping: Bool = false) throws(Debuggee.Error)
      -> (address: UInt64, reason: Debuggee.StopReason) {
    if si_code == SI_KERNEL || si_code == TRAP_BRKPT {
      return try (ABI.breakpoint(program), .breakpoint)
    }
    let address = if si_code == TRAP_HWBKPT {
      withUnsafePointer(to: self) { UInt64(dsx_siginfo_address($0)) }
    } else {
      program
    }
    return switch si_code {
    case ...0: (address, stepping ? .trace : .signal(SIGTRAP))
    case TRAP_TRACE: (address, .trace)
    default: (address, fallback)
    }
  }

  @inline(__always)
  internal func completes(_ registers: borrowing LinuxGeneralRegisters,
                          at address: UInt64) -> Bool {
    guard ABI.completes(si_code) else {
      return false
    }
    if si_code == SI_USER {
      guard generated(by: 0) else {
        return false
      }
    }
    return UInt64(registers.program) == address
  }

  @inline(__always)
  internal func pending(_ registers: borrowing LinuxGeneralRegisters,
                        at address: UInt64) -> Bool {
    let program = UInt64(registers.program)
    return completes(registers, at: address) || kernel && program == address
  }

  private var kernel: Bool {
    si_code == SI_KERNEL || si_code == SI_USER && generated(by: 0)
  }
}
#endif
