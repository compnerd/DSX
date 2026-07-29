// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(x86_64)
internal import Darwin

extension HardwareBreakpoint {
  internal static var features: StaticString {
    "x86_64"
  }

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
  internal func step(_ selection: Debuggee.Thread.Selection,
                     process: ProcessIdentifier,
                     threads: borrowing DarwinThreadList,
                     request: inout CInt) throws(Debuggee.Error)
      -> ProcessThreadIdentifier? {
    request = kPTStep
    return nil
  }

  internal mutating func step(_: borrowing Debuggee.Continuations,
                              process _: ProcessIdentifier,
                              threads _: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
  }

  internal mutating func finish(_: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
  }

  internal static func fault(_: CInt, process _: ProcessIdentifier,
                             threads _: borrowing DarwinThreadList)
      throws(Debuggee.Error) -> Debuggee.Event? {
    nil
  }

  internal static func trap(_: CInt, event: consuming Debuggee.Event,
                            stepping _: Bool,
                            threads _: borrowing DarwinThreadList,
                            breakpoints _: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) -> Debuggee.Event {
    consume event
  }

  internal func prepare(_: borrowing Debuggee.Continuations,
                        threads _: borrowing DarwinThreadList)
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
