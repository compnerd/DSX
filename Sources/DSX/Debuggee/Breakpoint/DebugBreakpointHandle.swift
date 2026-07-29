// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum DebugBreakpointHandle: Sendable {
  case software(SoftwareBreakpoint)
  case hardware

  internal init(_ process: ProcessIdentifier, _ breakpoint: BreakpointSite,
                control: borrowing NativeDebugControl = NativeDebugControl())
      throws(Debuggee.Error) {
    switch breakpoint.kind {
    case .software:
      self = try .software(SoftwareBreakpoint(process, breakpoint,
                                              control: control))
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
                       control: inout NativeDebugControl)
      throws(Debuggee.Error) {
    switch self {
    case let .software(handle):
      try handle.enable(process, breakpoint, thread: thread, control: control)
    case .hardware:
      try control.breakpoint(process, site: breakpoint, thread: thread,
                             enabled: true)
    }
  }

  internal func disable(_ process: ProcessIdentifier,
                        _ breakpoint: BreakpointSite,
                        thread: ProcessThreadIdentifier?,
                        control: inout NativeDebugControl)
      throws(Debuggee.Error) {
    switch self {
    case let .software(handle):
      try handle.disable(process, breakpoint, thread: thread, control: control)
    case .hardware:
      try control.breakpoint(process, site: breakpoint, thread: thread,
                             enabled: false)
    }
  }

  internal func hit(_ stop: Debuggee.Stop, _ breakpoint: BreakpointSite,
                    control: borrowing NativeDebugControl)
      throws(Debuggee.Error) -> Bool {
    switch self {
    case .software: breakpoint.hit(stop)
    case .hardware: try control.hit(stop, site: breakpoint)
    }
  }
}
