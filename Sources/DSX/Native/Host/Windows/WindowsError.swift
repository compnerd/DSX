// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal enum WindowsError {
  internal static func memory(_ code: DWORD) -> Debuggee.Error {
    switch code {
    case ERROR_INVALID_ADDRESS, ERROR_PARTIAL_COPY: .memory
    default: debuggee(code, invalid: .process)
    }
  }

  internal static func debuggee(_ code: DWORD) -> Debuggee.Error {
    switch code {
    case ERROR_ACCESS_DENIED: .access
    case ERROR_CALL_NOT_IMPLEMENTED, ERROR_NOT_SUPPORTED: .unsupported
    default: .system(CInt(bitPattern: code))
    }
  }

  internal static func debuggee(_ code: DWORD,
                                invalid: Debuggee.Error) -> Debuggee.Error {
    switch code {
    case ERROR_ACCESS_DENIED: .access
    case ERROR_INVALID_PARAMETER, ERROR_NOT_FOUND: invalid
    case ERROR_CALL_NOT_IMPLEMENTED, ERROR_NOT_SUPPORTED: .unsupported
    default: .system(CInt(bitPattern: code))
    }
  }
}
#endif
