// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims

extension Debuggee.Event {
  internal init(_ record: borrowing dsx_exception_record,
                process: ProcessIdentifier, threads: borrowing DarwinThreadList,
                breakpoints: borrowing ActiveBreakpoints)
      throws(Debuggee.Error) {
    let thread = try identity(record.thread)
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    let codes = record.codes
    let count = Int(record.count)
    let address = UInt64(bitPattern: count > 1 ? codes.1 : 0)
    let type = UInt64(record.type)
    let data = Debuggee.ExceptionData(count: count) { index in
      switch index {
      case 0: UInt64(bitPattern: codes.0)
      case 1: UInt64(bitPattern: codes.1)
      default: 0
      }
    }
    let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: address),
                               code: type, data: data, domain: .mach)
    switch record.type {
    case EXC_BREAKPOINT:
      let status = UnixWaitStatus(stopped: SIGTRAP).rawValue
      let event =
          Debuggee.Event(status: status, process: process, thread: thread)
      let translated =
          try DarwinDebugControl.trap(status, event: event, stepping: true,
                                      thread: record.thread,
                                      code: codes.0, threads: threads,
                                      breakpoints: breakpoints)
      guard case .stopped(let stop) = translated else {
        throw .state
      }
      let address = stop.fault?.address ?? fault.address
      let detail = Debuggee.Fault(address: address, code: fault.code,
                                  data: fault.data, domain: fault.domain)
      self = .stopped(stop.refined(reason: stop.reason, fault: detail,
                                   breakpoint: stop.breakpoint))
    case EXC_BAD_ACCESS:
      self = .stopped(Debuggee.Stop(thread: identifier,
                                    reason: .exception(0x91), fault: fault))
    case EXC_SOFTWARE where count > 1 && codes.0 == EXC_SOFT_SIGNAL:
      if codes.1 == SIGTRAP, try process.executed {
        self = .executed(identifier)
        return
      }
      self = .stopped(Debuggee.Stop(thread: identifier,
                                    reason: .signal(CInt(codes.1))))
    default:
      self = .stopped(Debuggee.Stop(thread: identifier,
                                    reason: .exception(type), fault: fault))
    }
  }

  internal init(interruption record: borrowing dsx_exception_record,
                process: ProcessIdentifier) throws(Debuggee.Error) {
    let thread = try identity(record.thread)
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    self = .stopped(Debuggee.Stop(thread: identifier, reason: .interrupt))
  }
}
#endif
