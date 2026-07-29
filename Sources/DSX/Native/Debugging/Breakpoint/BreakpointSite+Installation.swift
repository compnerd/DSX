// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension BreakpointSite {
  internal var installation: BreakpointSite {
    var kind = kind
    var size = size
#if arch(i386) || arch(x86_64)
    if kind == .watchpoint(.read) {
      kind = .watchpoint(.readwrite)
    }
#elseif arch(arm64)
    if kind == .software, size == 1 {
      size = 4
    }
#endif
    return BreakpointSite(address: address, size: size, kind: kind)
  }
}
