// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
internal struct WaitHandle: Sendable {
  internal let descriptor: CInt

  internal init(_ descriptor: CInt) {
    self.descriptor = descriptor
  }
}
#endif

internal enum WaitResult: Equatable, Sendable {
  case channel
  case event
  case timeout
}
