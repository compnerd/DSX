// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal struct WindowsHandle: ~Copyable, @unchecked Sendable {
  internal let value: HANDLE

  internal init(_ value: HANDLE) {
    self.value = value
  }

  internal init?(_ value: HANDLE?) {
    guard let value else {
      return nil
    }
    if value == INVALID_HANDLE_VALUE {
      return nil
    }
    self.value = value
  }

  deinit {
    _ = CloseHandle(value)
  }
}

extension ProcessIdentifier {
  @_transparent
  internal var native: DWORD {
    get throws(Debuggee.Error) {
      guard rawValue <= UInt64(DWORD.max) else {
        throw .process
      }
      return DWORD(rawValue)
    }
  }
}

extension ThreadIdentifier {
  @_transparent
  internal var native: DWORD {
    get throws(Debuggee.Error) {
      guard rawValue <= UInt64(DWORD.max) else {
        throw .thread
      }
      return DWORD(rawValue)
    }
  }
}
#endif
