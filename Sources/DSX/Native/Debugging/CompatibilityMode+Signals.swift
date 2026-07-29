// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

extension CompatibilityMode {
  @inline(__always)
  internal func signal(_ signal: CInt) -> UInt8 {
    self == .lldb ? UInt8(truncatingIfNeeded: signal)
        : SignalCatalog.gdb(signal)
  }

  internal func native(_ signal: UInt64) -> CInt? {
    guard signal <= UInt8.max else {
      return nil
    }
    return self == .lldb ? CInt(signal) : SignalCatalog.native(signal)
  }

  internal func signal(_ reason: Debuggee.StopReason) -> UInt8 {
    switch reason {
    case .interrupt:
#if os(Windows)
      0x02
#else
      self == .lldb ? UInt8(SIGSTOP) : 0x02
#endif
    case .signal(let value):
      signal(value)
    case .exception(let code):
      code == 0x91 ? 0x91 : 0x05
    case .library:
      // GDB identifies the event by its library field. LLDB refreshes images
      // from that field but treats a nonzero signal as a separate user stop.
      self == .gdb ? 0x05 : 0
    case .breakpoint, .create, .executed, .fork, .spawn, .syscall, .trace,
         .vfork, .vforkdone, .watchpoint:
      0x05
    }
  }
}
