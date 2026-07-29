// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows) || !arch(x86_64)
extension NativeDebugControl {
  internal mutating func checkpoint(_: ProcessIdentifier)
      throws(Debuggee.Error) -> BreakpointSite? {
    nil
  }
}
#endif
