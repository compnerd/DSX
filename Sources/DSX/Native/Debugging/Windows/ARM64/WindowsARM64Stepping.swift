// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(arm64)
internal import WinSDK

/// CPSR.SS, the software-step flag at bit 21. See Arm® ARM, CPSR.
private let kCPSRSoftwareStep: DWORD = 1 << 21

extension CONTEXT {
  internal mutating func step() {
    Cpsr |= kCPSRSoftwareStep
  }
}

#endif
