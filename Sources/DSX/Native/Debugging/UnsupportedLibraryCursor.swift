// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Android) && !os(Linux)
internal struct UnsupportedLibraryCursor {
  internal init(_: ProcessIdentifier) throws(Debuggee.Error) {
    throw .unsupported
  }

  internal mutating func next() throws(Debuggee.Error) -> Debuggee.Library? {
    nil
  }
}
#endif
