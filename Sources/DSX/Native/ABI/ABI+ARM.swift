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

#if arch(arm64)
internal enum SPSR {
  /// Arm A-profile SPSR_EL1.SS, the software-step state at bit 21.
  internal static let SS: UInt32 = 0x00200000
}
#endif
