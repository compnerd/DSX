// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal struct WaitHandle: @unchecked Sendable {
  internal let value: HANDLE

  internal init(_ value: HANDLE) {
    self.value = value
  }

  internal func close() {
    _ = CloseHandle(value)
  }
}
#endif
