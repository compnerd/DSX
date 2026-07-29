// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(x86_64)
internal import Darwin

extension HardwareBreakpoint {
  internal static let features: StaticString = "x86_64"

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

extension DarwinDebugControl {
  internal func configure(_: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
  }

  internal func breakpoint(_: ProcessIdentifier,
                           site _: borrowing BreakpointSite,
                           thread _: ProcessThreadIdentifier?, enabled _: Bool)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  internal func hit(_: borrowing Debuggee.Stop,
                    site _: borrowing BreakpointSite) throws(Debuggee.Error)
      -> Bool {
    false
  }
}

#endif
