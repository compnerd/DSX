// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBRemoteSelection: Equatable, Sendable {
  internal var general: Debuggee.Thread.Selection
  internal var resume: Debuggee.Thread.Selection
  internal var stopped: ProcessThreadIdentifier?

  internal init(general: Debuggee.Thread.Selection = .any,
                resume: Debuggee.Thread.Selection = .any,
                stopped: ProcessThreadIdentifier? = nil) {
    self.general = general
    self.resume = resume
    self.stopped = stopped
  }

  internal func resolve(in debuggee: borrowing Debuggee)
      -> ProcessThreadIdentifier? {
    if let resolved = debuggee.resolve(general) {
      return resolved
    }
    guard let stopped, debuggee.alive(stopped) else {
      return nil
    }
    return stopped
  }

  internal func thread(_ requested: ProcessThreadIdentifier?,
                       in debuggee: borrowing Debuggee) throws(GDBHandlerError)
      -> ProcessThreadIdentifier {
    if let requested {
      return requested
    }
    guard let selected = resolve(in: debuggee) else {
      throw .debuggee(.thread)
    }
    return selected
  }
}
