// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension HardwareBreakpoint {
  internal static var features: StaticString {
    ""
  }

  internal static func advance(_: BreakpointKind) -> Bool {
    false
  }

  internal static var capacity: Int? {
    get throws(Debuggee.Error) {
      nil
    }
  }

  internal static func supports(_: BreakpointKind) -> Bool {
    false
  }
}

extension LinuxDebugControl {
  internal func watchpoints(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Int {
    guard self.process == process else {
      throw .process
    }
    return 0
  }

  internal func prepare(_: borrowing Debuggee.Continuations)
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

  internal func inherit(_: ProcessIdentifier, thread _: pid_t)
      throws(Debuggee.Error) {
  }
}
#endif
