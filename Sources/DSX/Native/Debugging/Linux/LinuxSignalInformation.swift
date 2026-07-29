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

  internal func address(for signal: CInt) -> UInt64? {
    let standard = si_code >= SEGV_MAPERR && si_code <= SEGV_PKUERR
    let present = switch signal {
    case SIGBUS: si_code >= BUS_ADRALN && si_code <= BUS_MCEERR_AO
    case SIGSEGV:
      standard || si_code == SEGV_MTEAERR || si_code == SEGV_MTESERR ||
          si_code == SEGV_CPERR || si_code == SI_KERNEL
    default: false
    }
    guard present else {
      return nil
    }
    return withUnsafePointer(to: self) { UInt64(dsx_siginfo_address($0)) }
  }
}
#endif
