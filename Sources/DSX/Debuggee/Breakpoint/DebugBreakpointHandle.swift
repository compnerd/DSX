// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum DebugBreakpointHandle: Sendable {
  case software(SoftwareBreakpoint)
  case hardware

  internal init(_ process: ProcessIdentifier, _ breakpoint: BreakpointSite)
      throws(Debuggee.Error) {
    switch breakpoint.kind {
    case .software:
      self = try .software(SoftwareBreakpoint(process, breakpoint))
    case .hardware, .watchpoint:
      guard HardwareBreakpoint.supports(breakpoint.kind) else {
        throw .unsupported
      }
      self = .hardware
    }
  }

  internal func enable(_ process: ProcessIdentifier,
                       _ breakpoint: BreakpointSite,
                       thread: ProcessThreadIdentifier?,
                       context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    switch self {
    case .software(let handle):
      try handle.enable(process, breakpoint)
    case .hardware:
      try context.breakpoint(process, site: breakpoint, thread: thread,
                             enabled: true)
    }
  }

  internal func disable(_ process: ProcessIdentifier,
                        _ breakpoint: BreakpointSite,
                        thread: ProcessThreadIdentifier?,
                        context: inout NativeDebugControl)
      throws(Debuggee.Error) {
    switch self {
    case .software(let handle):
      try handle.disable(process, breakpoint)
    case .hardware:
      try context.breakpoint(process, site: breakpoint, thread: thread,
                             enabled: false)
    }
  }

  internal func hit(_ stop: Debuggee.Stop, _ breakpoint: BreakpointSite,
                    context: inout NativeDebugControl)
      throws(Debuggee.Error) -> Bool {
    switch self {
    case .software: breakpoint.hit(stop)
    case .hardware: try context.hit(stop, site: breakpoint)
    }
  }
}
