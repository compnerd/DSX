// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum RegisterAccess {
  case unavailable
  case immutable
  case mutable
}

#if os(Windows) || os(Linux) || os(Android) || os(FreeBSD) || os(OpenBSD)
extension NativeRegisterState {
  internal static func access(_: RegisterIdentifier) -> RegisterAccess {
    .mutable
  }
}
#endif
