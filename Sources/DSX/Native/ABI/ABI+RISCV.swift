// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(riscv64)
extension ABI {
  internal static var watchpoint: StaticString {
    "after"
  }

  internal static func role(_ register: RegisterRecord) -> RegisterRole? {
    register.role
  }

  internal static var machine: StaticString {
    "riscv64"
  }
}
#endif
