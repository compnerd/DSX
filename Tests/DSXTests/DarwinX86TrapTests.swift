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
#endif
