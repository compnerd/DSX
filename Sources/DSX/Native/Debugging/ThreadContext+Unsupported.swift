// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(anyAppleOS)
extension ProcessThreadIdentifier {
  internal func context(_ layout: Debuggee.Thread.Layout) throws(Debuggee.Error)
      -> Debuggee.Thread.Context {
    throw .unsupported
  }
}
#endif
