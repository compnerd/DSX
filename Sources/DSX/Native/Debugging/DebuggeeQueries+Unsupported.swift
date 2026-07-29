// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Android) && !os(Linux)
extension ProcessIdentifier {
  internal func auxiliary(offset: UInt64, limit: Int,
                          into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> ReadStatus {
    throw .unsupported
  }
}

extension ProcessThreadIdentifier {
  internal func signal(offset: UInt64, limit: Int,
                       into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> ReadStatus {
    throw .unsupported
  }
}
#endif

#if !os(Windows)
extension ProcessThreadIdentifier {
  internal var tib: Debuggee.Address {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }
}
#endif

#if !os(anyAppleOS)
extension ProcessIdentifier {
  internal var loader: Debuggee.Loader {
    get throws(Debuggee.Error) {
      throw .unsupported
    }
  }
}
#endif
