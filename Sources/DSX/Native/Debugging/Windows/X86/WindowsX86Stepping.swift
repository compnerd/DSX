// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && (arch(i386) || arch(x86_64))
internal import WinSDK

/// EFLAGS.TF, the trap flag at bit 8. See Intel® SDM, EFLAGS register.
private let kEFlagsTrap: DWORD = 1 << 8

extension CONTEXT {
  internal mutating func step() {
    EFlags |= kEFlagsTrap
  }
}

#endif
