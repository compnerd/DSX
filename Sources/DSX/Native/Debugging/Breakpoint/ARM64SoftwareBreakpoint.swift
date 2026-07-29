// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if arch(arm64)
extension ABI {
  internal static func size(_ address: Debuggee.Address,
                            requested: Int) throws(Debuggee.Error) -> Int {
    guard requested == 1 || requested == 4,
        address.rawValue.isMultiple(of: 4) else {
      throw .breakpoint
    }
    return 4
  }
}
#endif
