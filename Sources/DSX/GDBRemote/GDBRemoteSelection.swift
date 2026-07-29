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
}
