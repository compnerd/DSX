// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

/// Data address bits ignored by Linux hardware watchpoints.
internal struct LinuxARM64AddressMask {
  internal let data: UInt64

  internal init(_ thread: pid_t) {
    // PAC is optional. Without the regset, Linux still ignores data tags.
    var mask = InlineArray<2, UInt64> { _ in 0 }
    let result: Int? =
        try? withUnsafeMutableBytes(of: &mask, { bytes throws(Debuggee.Error) in
          try bytes.transfer(PTRACE_GETREGSET, note: NT_ARM_PAC_MASK,
                             thread: thread)
        })
    let value = result == nil ? 0 : mask[0]
    data = value | 0xff00_0000_0000_0000
  }
}
#endif
