// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal enum WindowsDebugDisposition: Sendable {
  case handled
  case unhandled

  internal var value: DWORD {
    switch self {
    case .handled:
      DBG_CONTINUE
    case .unhandled:
      DBG_EXCEPTION_NOT_HANDLED
    }
  }
}

extension WindowsDebugControl {
  private static let kName: UInt64 = 0x406d1388

  internal static func disposition(_ event: borrowing DEBUG_EVENT)
      -> WindowsDebugDisposition? {
    guard event.dwDebugEventCode == EXCEPTION_DEBUG_EVENT,
        event.u.Exception.dwFirstChance > 0 else {
      return nil
    }
    let code = event.u.Exception.ExceptionRecord.ExceptionCode
    switch code {
    case EXCEPTION_BREAKPOINT, EXCEPTION_SINGLE_STEP,
         kStatusWX86Breakpoint, kStatusWX86SingleStep:
      return nil
    default:
      return UInt64(code) == kName ? .handled : .unhandled
    }
  }
}
#endif
