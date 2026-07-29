// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee.Stop {
  internal consuming func unclaimed() -> Debuggee.Stop {
#if os(anyAppleOS)
    // Resolve ownership before turning an embedded trap into its native
    // exception. Installed breakpoints must retain breakpoint semantics.
    if reason == .breakpoint, let fault, fault.domain == .mach,
        case .some = fault.data, let code = fault.code {
      return refined(reason: .exception(code), fault: fault, breakpoint: nil)
    }
#endif
    return self
  }
}
