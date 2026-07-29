// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum HardwareBreakpoint {
  internal static func supports(_ kind: BreakpointKind,
                                available: Bool) -> Bool {
    guard available else {
      return false
    }
    return switch kind {
    case .hardware, .watchpoint: true
    case .software: false
    }
  }
}
