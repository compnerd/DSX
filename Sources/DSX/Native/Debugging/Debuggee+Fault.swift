// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif !os(Windows)
internal import Glibc
#endif

extension Debuggee.Fault {
  internal func description(_ signal: CInt)
      -> (name: StaticString, detail: StaticString?)? {
#if os(Windows)
    nil
#else
    guard domain == .posix else {
      return nil
    }
    let name: StaticString? = switch signal {
    case SIGBUS: "SIGBUS"
    case SIGSEGV: "SIGSEGV"
    default: nil
    }
    guard let name else {
      return nil
    }
    return (name, detail(signal))
#endif
  }

  internal var location: Debuggee.Address? {
#if os(Android) || os(Linux)
    // Asynchronous MTE reports do not identify the faulting access.
    if domain == .posix, code == UInt64(SEGV_MTEAERR) {
      return nil
    }
#endif
    return address
  }

#if !os(Windows)
  private func detail(_ signal: CInt) -> StaticString? {
#if os(Android) || os(Linux)
    guard let code else {
      return nil
    }
    return switch (signal, code) {
    case (SIGBUS, UInt64(BUS_ADRALN)): "illegal alignment"
    case (SIGBUS, UInt64(BUS_ADRERR)): "illegal address"
    case (SIGBUS, UInt64(BUS_OBJERR)): "hardware error"
    case (SIGBUS, UInt64(BUS_MCEERR_AR)):
      "hardware memory error, action required"
    case (SIGBUS, UInt64(BUS_MCEERR_AO)):
      "hardware memory error, action optional"
    case (SIGSEGV, UInt64(SEGV_MAPERR)): "address not mapped to object"
    case (SIGSEGV, UInt64(SEGV_ACCERR)): "invalid permissions for mapped object"
    case (SIGSEGV, UInt64(SEGV_BNDERR)): "failed address bounds checks"
    case (SIGSEGV, UInt64(SEGV_PKUERR)): "failed protection key checks"
    case (SIGSEGV, UInt64(SEGV_MTEAERR)): "async tag check fault"
    case (SIGSEGV, UInt64(SEGV_MTESERR)): "sync tag check fault"
    case (SIGSEGV, UInt64(SEGV_CPERR)): "control protection fault"
    case (SIGSEGV, UInt64(SI_KERNEL)): "invalid address"
    default: nil
    }
#else
    nil
#endif
  }
#endif
}
