// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(OpenBSD) && arch(x86_64)
extension HardwareBreakpoint {
  internal static var features: StaticString {
    ""
  }

  internal static func advance(_: BreakpointKind) -> Bool {
    false
  }

  internal static var capacity: Int? {
    get throws(Debuggee.Error) {
      0
    }
  }

  internal static func supports(_: BreakpointKind) -> Bool {
    false
  }
}
#endif
