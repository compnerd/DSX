// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
@preconcurrency internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

internal enum UnixWaitStatus {
  internal static func stopped(_ status: CInt) -> Bool {
    status & kWaitSignalMask == kWaitStopped
  }

  internal static func signal(_ status: CInt) -> CInt {
    status >> kWaitStatusShift & kWaitStatusMask
  }

  internal static func exited(_ status: CInt) -> Bool {
    status & kWaitSignalMask == 0
  }

  internal static func exit(_ status: CInt) -> Debuggee.Exit? {
    switch (exited(status), signalled(status)) {
    case (true, _): .exited(code(status))
    case (_, true): .signalled(term(status))
    default: nil
    }
  }

  private static func code(_ status: CInt) -> CInt {
    status >> kWaitStatusShift & kWaitStatusMask
  }

  internal static func signalled(_ status: CInt) -> Bool {
    let signal = status & kWaitSignalMask
    return signal > 0 && signal < kWaitStopped
  }

  private static func term(_ status: CInt) -> CInt {
    status & kWaitSignalMask
  }
}
#endif
