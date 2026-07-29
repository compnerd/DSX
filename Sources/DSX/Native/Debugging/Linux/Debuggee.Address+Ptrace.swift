// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension Debuggee.Address {
  internal func peek(_ thread: pid_t, request: CInt = PTRACE_PEEKDATA,
                     failure: (CInt) -> Debuggee.Error = LinuxProcFS.failure)
      throws(Debuggee.Error) -> CLong {
    let address = try UnsafeMutableRawPointer(bitPattern: native)
    errno = 0
    let word = ptrace(request, thread, address, nil)
    if word == -1 {
      guard errno == 0 else {
        throw failure(errno)
      }
    }
    return word
  }

  internal func poke(_ thread: pid_t, word: CLong,
                     request: CInt = PTRACE_POKEDATA,
                     failure: (CInt) -> Debuggee.Error = LinuxProcFS.failure)
      throws(Debuggee.Error) {
    let address = try UnsafeMutableRawPointer(bitPattern: native)
    let data = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: word))
    guard ptrace(request, thread, address, data) == 0 else {
      throw failure(errno)
    }
  }
}
#endif
