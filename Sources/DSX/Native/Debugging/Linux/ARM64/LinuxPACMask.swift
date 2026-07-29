// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

/// Linux's user_pac_mask payload, in NT_ARM_PAC_MASK register order.
internal struct LinuxPACMask: Sendable {
  internal private(set) var data: UInt64 = 0
  internal private(set) var instruction: UInt64 = 0

  internal init(_ thread: pid_t) throws(Debuggee.Error) {
    _ = try withUnsafeMutableBytes(of: &self, { bytes throws(Debuggee.Error) in
      try bytes.transfer(PTRACE_GETREGSET, note: NT_ARM_PAC_MASK,
                         thread: thread)
    })
  }
}
#endif
