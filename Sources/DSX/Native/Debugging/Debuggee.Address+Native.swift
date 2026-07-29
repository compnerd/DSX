// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee.Address {
  internal var native: UInt {
    get throws(Debuggee.Error) {
      guard let value = UInt(exactly: rawValue) else {
        throw .memory
      }
      return value
    }
  }
}
