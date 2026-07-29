// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(arm) || arch(arm64)
extension ABI {
  internal static var watchpoint: StaticString {
    "before"
  }

  internal static func role(_ register: RegisterRecord) -> RegisterRole? {
    register.role
  }

#if arch(arm)
  internal static var machine: StaticString {
    "arm"
  }
#else
  internal static var machine: StaticString {
#if os(Android) || os(Linux)
    "aarch64"
#else
    "arm64"
#endif
  }
#endif
}
#endif
