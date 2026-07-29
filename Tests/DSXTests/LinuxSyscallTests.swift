// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxSyscallTests {
#if arch(x86_64) || arch(arm64)
  @Test
  internal func injection() throws {
#if os(Android)
    let executable = "/system/bin/sleep"
#else
    let executable = "/bin/sleep"
#endif
    var arguments = [strdup(executable), strdup("30"), nil]
    defer {
      free(arguments[0])
      free(arguments[1])
    }
    var child: pid_t = 0
    let status =
        posix_spawn(&child, executable, nil, nil, &arguments, environ)
    try #require(status == 0)
    defer {
      _ = DSX::kill(child, SIGKILL)
      _ = waitpid(child, nil, 0)
    }
    let process = ProcessIdentifier(rawValue: UInt64(child))
    var control = LinuxDebugControl()
    try control.attach(process)
    defer { try? control.close() }
    guard case .stopped = try control.event() else {
      Issue.record("attachment did not report a stop")
      return
    }
    let address =
        try LinuxMemory.allocate(process, size: 4096, readable: true,
                                 writable: true, executable: false,
                                 control: &control)
    try LinuxMemory.deallocate(process, address: address, size: 4096,
                               control: &control)
    try #require(DSX::kill(child, SIGUSR1) == 0)
    #expect(throws: Debuggee.Error.state) {
      try LinuxMemory.allocate(process, size: 4096, readable: true,
                               writable: true, executable: false,
                               control: &control)
    }
    guard case .stopped(let stop) = try control.event() else {
      Issue.record("injected syscall lost the pending signal")
      return
    }
    #expect(stop.reason == .signal(SIGUSR1))
    #expect(stop.thread.process == process)
  }
#endif

  @Test
  internal func pending() throws(Debuggee.Error) {
    var control = LinuxDebugControl()
    control.status = 0
    control.thread = 100
    let actions = Array<Debuggee.Continuation>()
    try control.resume(actions.span)
    #expect(control.status == 0)
    #expect(control.thread == 100)
  }

  @Test
  internal func ownership() throws(Debuggee.Error) {
    let parent = ProcessIdentifier(rawValue: 100)
    let child = ProcessIdentifier(rawValue: 200)
    var control = LinuxDebugControl()
    control.process = parent
    control.children.insert(200)
    control.owners = [100: parent, 101: parent, 200: child, 201: child]
    control.stopped = [101, 200, 201]
    #expect(try control.thread(parent) == 101)
    #expect(try control.thread(child) == 200)
    control.stopped.remove(200)
    #expect(try control.thread(child) == 201)
    control.stopped.remove(101)
    #expect(throws: Debuggee.Error.state) {
      try control.thread(parent)
    }
    #expect(throws: Debuggee.Error.process) {
      try control.thread(ProcessIdentifier(rawValue: 300))
    }
  }

  @Test(arguments: [UInt32(0x7fff_ffff), 0x8000_0000, 0xb000_0000, 0xffff_f000])
  internal func addresses(_ value: UInt32) throws(Debuggee.Error) {
#if arch(arm) || arch(i386)
    let raw = UInt64(bitPattern: Int64(Int32(bitPattern: value)))
#else
    let raw = UInt64(value)
#endif
    #expect(try LinuxDebugControl.validate(raw) == UInt64(value))
  }

  @Test(arguments: [UInt64(1), 4095])
  internal func errors(_ code: UInt64) {
    #expect(throws: Debuggee.Error.self) {
      try LinuxDebugControl.validate(0 &- code)
    }
  }
}
#endif
