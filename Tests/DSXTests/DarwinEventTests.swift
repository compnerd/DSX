// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims
internal import Testing
@testable internal import DSX

@Suite internal struct DarwinEventTests {
  @Test(arguments: [Debuggee.StopReason.breakpoint, .trace])
  internal func unclaimed(_ reason: Debuggee.StopReason) throws {
    let identifier =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 1),
                                thread: ThreadIdentifier(rawValue: 2))
    let data = Debuggee.ExceptionData(count: 2) { UInt64($0 + 1) }
    let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: 0x1000),
                               code: UInt64(EXC_BREAKPOINT), data: data,
                               domain: .mach)
    let control = DarwinDebugControl()
    let table = BreakpointTable()
    let stop = Debuggee.Stop(thread: identifier, reason: reason, fault: fault)
    let result = try table.classify(stop, context: control)
    let expected: Debuggee.StopReason = reason == .breakpoint
        ? .exception(UInt64(EXC_BREAKPOINT)) : .trace
    #expect(result.reason == expected)
    #expect(result.fault?.address == fault.address)
    #expect(result.breakpoint == nil)

    let breakpoint = BreakpointIdentifier(rawValue: 3)
    let owned = Debuggee.Stop(thread: identifier, reason: reason, fault: fault,
                              breakpoint: breakpoint)
    let retained = try table.classify(owned, context: control)
    #expect(retained.reason == reason)
    #expect(retained.breakpoint == breakpoint)
  }

#if arch(arm64)
  @Test(arguments: [true, false])
  internal func watchpoint(_ owned: Bool) throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    let threads = try DarwinThreadList(process)
    let thread = mach_thread_self()
    defer { _ = mach_port_deallocate(mach_task_self_, thread) }
    var record = dsx_exception_record()
    record.thread = thread
    record.type = EXC_BREAKPOINT
    record.count = 2
    record.codes = (Int64(EXC_ARM_DA_DEBUG), 0x1002)
    let site = BreakpointSite(address: Debuggee.Address(rawValue: 0x1000),
                              size: 4, kind: .watchpoint(.write))
    let sites = owned ? [ActiveBreakpoint(site: site, thread: nil)] : []
    let event = try Debuggee.Event(record, process: process, threads: threads,
                                   breakpoints: sites)
    guard case .stopped(let stop) = event else {
      Issue.record("Mach data breakpoint must report a stop")
      return
    }
    let reason: Debuggee.StopReason =
        owned ? .watchpoint(.write, site.address)
              : .exception(UInt64(EXC_BREAKPOINT))
    #expect(stop.reason == reason)
    #expect(try stop.thread.thread == ThreadIdentifier(mach: thread))
    #expect(stop.fault?.address.rawValue == 0x1002)
    #expect(stop.fault?.code == UInt64(EXC_BREAKPOINT))
  }
#endif

  @Test internal func outputFailureRetainsExit() throws {
    let process = ProcessIdentifier(rawValue: UInt64(getpid()))
    var control = DarwinDebugControl()
    control.process = process
    control.status = 0
    control.reader = -1
    #expect(throws: Debuggee.Error.self) {
      try control.event()
    }
    let event = try control.event(output: false)
    guard case .exited(let identifier, _) = event else {
      Issue.record("The reaped exit must remain available after a read failure")
      return
    }
    #expect(identifier == process)
    #expect(control.process == nil)
    #expect(control.deferred == nil)
  }
}
#endif
