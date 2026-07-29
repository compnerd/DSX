// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct ActiveBreakpoint: Sendable {
  internal let site: BreakpointSite
  internal let thread: ProcessThreadIdentifier?

  internal init(site: BreakpointSite, thread: ProcessThreadIdentifier?) {
    self.site = site
    self.thread = thread
  }
}

internal typealias ActiveBreakpoints = Array<ActiveBreakpoint>
