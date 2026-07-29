// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc

internal struct BSDDebugControl: Sendable {
  internal var process: ProcessIdentifier?
  internal var attached = false
  internal var status: CInt?
  internal var request: CInt?
  internal var breakpoints = ActiveBreakpoints()
  internal var reader: CInt?
  internal var output: Debuggee.Output?
  internal var release = false
}

extension BSDDebugControl {
  internal mutating func interrupt(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    guard DSX::kill(identifier, SIGSTOP) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    request = nil
  }

  internal mutating func collect() -> Debuggee.Event? {
    nil
  }
}
#endif
