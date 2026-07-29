// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal enum WindowsRedirection: ~Copyable {
  case borrowed(HANDLE?)
  case owned(WindowsHandle)

  internal var value: HANDLE? {
    borrowing get {
      switch self {
      case .borrowed(let value): value
      case .owned(let handle): handle.value
      }
    }
  }
}
#endif
