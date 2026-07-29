// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct UnixWaitStatus {
  private static let kSignalMask: CInt = 0x7f
  private static let kStopped: CInt = 0x7f
  private static let kStatusShift: CInt = 8
  private static let kStatusMask: CInt = 0xff

  internal let rawValue: CInt

  internal init(_ value: CInt) {
    rawValue = value
  }

  internal init(stopped signal: CInt) {
    rawValue = UnixWaitStatus.kStopped | signal << UnixWaitStatus.kStatusShift
  }

  internal var stopped: Bool {
#if os(anyAppleOS) || os(FreeBSD)
    rawValue & UnixWaitStatus.kSignalMask == UnixWaitStatus.kStopped &&
        continued == false
#else
    rawValue & UnixWaitStatus.kStatusMask == UnixWaitStatus.kStopped &&
        continued == false
#endif
  }

  internal var continued: Bool {
#if os(anyAppleOS)
    // Darwin encodes SIGCONT as a distinguished stopped status.
    rawValue & UnixWaitStatus.kSignalMask == UnixWaitStatus.kStopped &&
        rawValue >> UnixWaitStatus.kStatusShift == 0x13
#elseif os(FreeBSD)
    // FreeBSD reserves the unshifted SIGCONT value instead.
    rawValue == 0x13
#elseif os(OpenBSD)
    rawValue & 0xffff == 0xffff
#else
    rawValue == 0xffff
#endif
  }

  internal var signal: CInt {
    rawValue >> UnixWaitStatus.kStatusShift & UnixWaitStatus.kStatusMask
  }

  internal var exit: Debuggee.Exit? {
    if continued {
      return nil
    }
    let signal = rawValue & UnixWaitStatus.kSignalMask
    return switch signal {
    case 0: .exited(self.signal)
    case 1 ..< UnixWaitStatus.kStopped: .signalled(signal)
    default: nil
    }
  }
}
