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

extension WindowsDebugDisposition {
  private static let kName: DWORD = 0x406d1388

  internal init?(_ event: borrowing DEBUG_EVENT) {
    guard event.dwDebugEventCode == EXCEPTION_DEBUG_EVENT,
        event.u.Exception.dwFirstChance > 0 else {
      return nil
    }
    let code = event.u.Exception.ExceptionRecord.ExceptionCode
    switch code {
    case EXCEPTION_BREAKPOINT, EXCEPTION_SINGLE_STEP,
         STATUS_WX86_BREAKPOINT, STATUS_WX86_SINGLE_STEP:
      return nil
    default:
      self = code == WindowsDebugDisposition.kName ? .handled : .unhandled
    }
  }
}
#endif
