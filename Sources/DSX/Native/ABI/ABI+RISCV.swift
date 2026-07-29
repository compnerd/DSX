// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(riscv64)
extension ABI {
  // RISC-V places the frame record below FP, not at FP.
  internal static let frame: Bool = false

  internal static let watchpoint: StaticString = "after"

  internal static func role(_ register: RegisterRecord) -> RegisterRole? {
    register.role
  }

  internal static let machine: StaticString = "riscv64"
}
#endif
