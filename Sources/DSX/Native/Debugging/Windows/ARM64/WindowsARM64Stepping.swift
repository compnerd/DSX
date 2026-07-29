// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(arm64)
internal import WinSDK

extension CONTEXT {
  internal mutating func step() {
    Cpsr |= SPSR.SS
  }
}

#endif
