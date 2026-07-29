// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(x86_64)
internal import Darwin
internal import Testing
@testable internal import DSX

@Suite
internal struct DarwinX86TrapTests {
  @Test
  internal func breakpoint() throws(Debuggee.Error) {
    let process = ProcessIdentifier(rawValue: 1)
    let thread = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 2))
    let stop = Debuggee.Stop(thread: thread, reason: .trace)
    var registers = x86_thread_state64_t()
    registers.__rip = 0x1001
    let trap = try registers.trap(stop, code: Int64(EXC_I386_BPT))
    #expect(trap.reason == .breakpoint)
    #expect(trap.thread == thread)
    #expect(trap.fault?.address.rawValue == 0x1000)
    #expect(registers.__rip == 0x1001)
    let site = BreakpointSite(address: Debuggee.Address(rawValue: 0x1000),
                              size: 1, kind: .software)
    #expect(site.hit(trap))
    #expect(trap.breakpoint == nil)

    let step = try registers.trap(stop, code: Int64(EXC_I386_SGL))
    #expect(step.reason == .trace)
    #expect(site.hit(step) == false)
    registers.__rip = 0
    #expect(throws: Debuggee.Error.register) {
      _ = try registers.trap(stop, code: Int64(EXC_I386_BPT))
    }
  }

  @Test
  internal func stepping() {
    var registers = x86_thread_state64_t()
    registers.__rflags = 0x202
    registers.step(enabled: true)
    #expect(registers.__rflags == 0x302)
    registers.step(enabled: false)
    #expect(registers.__rflags == 0x202)
  }
}

@Suite
internal struct DarwinX86WatchpointTests {
  @Test
  internal func capacity() throws(Debuggee.Error) {
    #expect(try HardwareBreakpoint.capacity == 4)
    var state = x86_debug_state64_t()
    for index in 0 ..< 4 {
      let address = Debuggee.Address(rawValue: 0x1000 + UInt64(index))
      let site = BreakpointSite(address: address,
                                size: 1, kind: .watchpoint(.write))
      try state.insert(site)
    }
    #expect(state.__dr7 == 0x11110055)
    let extra = BreakpointSite(address: Debuggee.Address(rawValue: 0x2000),
                               size: 1, kind: .watchpoint(.write))
    #expect(throws: Debuggee.Error.breakpoint) {
      try state.insert(extra)
    }
    #expect(state.__dr7 == 0x11110055)
  }

  @Test
  internal func duplicate() throws(Debuggee.Error) {
    let site = BreakpointSite(address: Debuggee.Address(rawValue: 0x1000),
                              size: 8, kind: .watchpoint(.readwrite))
    var state = x86_debug_state64_t()
    try state.insert(site)
    try state.insert(site)
    #expect(state.__dr0 == 0x1000)
    #expect(state.__dr7 == 0xb0001)
    #expect(try state.hit(site) == false)
    state.__dr6 = 1
    #expect(try state.hit(site))
    state.__dr6 = 2
    #expect(try state.hit(site) == false)
    state.__dr6 = 1
    state.__dr7 = 0
    #expect(try state.hit(site) == false)
  }

  @Test
  internal func inheritance() throws(Debuggee.Error) {
    let process = ProcessIdentifier(rawValue: 1)
    let first = ProcessThreadIdentifier(process: process,
                                        thread: ThreadIdentifier(rawValue: 2))
    let second = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 3))
    let global = BreakpointSite(address: Debuggee.Address(rawValue: 0x1000),
                                size: 1, kind: .hardware)
    let local = BreakpointSite(address: Debuggee.Address(rawValue: 0x2000),
                               size: 4, kind: .watchpoint(.write))
    var sites = ActiveBreakpoints()
    sites.update(global, thread: nil, enabled: true)
    sites.update(local, thread: first, enabled: true)
    let template = try x86_debug_state64_t(sites, thread: nil)
    #expect(template.__dr0 == 0x1000)
    #expect(template.__dr7 == 1)
    let selected = try x86_debug_state64_t(sites, thread: first)
    #expect(selected.__dr0 == 0x1000)
    #expect(selected.__dr1 == 0x2000)
    #expect(selected.__dr7 == 0xd00005)
    let other = try x86_debug_state64_t(sites, thread: second)
    #expect(other.__dr7 == template.__dr7)
    sites.update(global, thread: nil, enabled: false)
    sites.update(local, thread: first, enabled: false)
    let empty = try x86_debug_state64_t(sites, thread: first)
    #expect(empty.__dr0 == 0)
    #expect(empty.__dr6 == 0)
    #expect(empty.__dr7 == 0)
  }

  @Test
  internal func alignment() {
    var state = x86_debug_state64_t()
    let site = BreakpointSite(address: Debuggee.Address(rawValue: 0x1001),
                              size: 8, kind: .watchpoint(.write))
    #expect(throws: Debuggee.Error.breakpoint) {
      try state.insert(site)
    }
    #expect(state.__dr7 == 0)
  }

  @Test
  internal func classification() throws(Debuggee.Error) {
    let process = ProcessIdentifier(rawValue: 1)
    let thread = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 2))
    let other = ProcessThreadIdentifier(process: process,
                                        thread: ThreadIdentifier(rawValue: 3))
    let address = Debuggee.Address(rawValue: 0x2000)
    let site = BreakpointSite(address: address, size: 4,
                              kind: .watchpoint(.write))
    var sites = ActiveBreakpoints()
    sites.update(site, thread: thread, enabled: true)
    var state = try x86_debug_state64_t(sites, thread: thread)
    state.__dr6 = 1
    let stop = Debuggee.Stop(thread: thread, reason: .trace)
    let trap = try state.trap(stop, breakpoints: sites)
    #expect(trap.reason == .watchpoint(.write, address))
    #expect(trap.fault?.address == address)
    let unrelated = Debuggee.Stop(thread: other, reason: .trace)
    let ignored = try state.trap(unrelated, breakpoints: sites)
    #expect(ignored.reason == .trace)
    #expect(ignored.fault == nil)
    state.__dr6 = 0
    let step = Debuggee.Stop(thread: thread, reason: .trace)
    #expect(try state.trap(step, breakpoints: sites).reason == .trace)
  }
}
#endif
