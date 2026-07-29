// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(arm) || arch(arm64)
extension ABI {
  internal static var frame: Bool {
#if arch(arm64)
    true
#else
    // ARM32 frame-record conventions vary; do not infer a layout from width.
    false
#endif
  }

  internal static let watchpoint: StaticString = "before"

  internal static func role(_ register: RegisterRecord) -> RegisterRole? {
    register.role
  }

  internal static var machine: StaticString {
#if arch(arm)
    "arm"
#elseif os(Android) || os(Linux)
    "aarch64"
#else
    "arm64"
#endif
  }
}
#endif
