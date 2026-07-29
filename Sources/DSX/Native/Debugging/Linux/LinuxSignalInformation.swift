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
                failure: (CInt) -> Debuggee.Error = UnixDebugProcess.failure)
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
    let standard = si_code >= kSEGV_MAPERR && si_code <= kSEGV_PKUERR
    return switch signal {
    case SIGBUS: si_code >= kBUS_ADRALN && si_code <= kBUS_OBJERR
    case SIGSEGV: standard || si_code == kSEGV_MTESERR || si_code == SI_KERNEL
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
#if arch(i386) || arch(x86_64)
    let expected = si_code == TRAP_BRKPT || si_code == TRAP_TRACE
#elseif arch(arm64)
    let kernel = si_code == SI_USER && generated(by: 0)
    let expected = si_code == TRAP_TRACE || kernel
#else
    let expected = si_code == TRAP_TRACE
#endif
    guard expected else {
      return false
    }
    return ABI.program(registers) == address
  }
}
#endif
