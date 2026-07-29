// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
extension NativeDebugControl {
  internal func images(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> NativeImageCursor {
    try NativeImageCursor(process)
  }

  internal mutating func libraries(_: Bool) {
  }
}
#endif
