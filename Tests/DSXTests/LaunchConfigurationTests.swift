// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

@testable internal import DSX
internal import Testing

@Suite
internal struct LaunchConfigurationTests {
  @Test
  internal func directory() {
    let inherited = PlatformSession()
    #expect(inherited.launch.directory == Host.directory)
    let fallback = PlatformSession(directory: "fallback")
    #expect(fallback.launch.directory == "fallback")
    let launch = Debuggee.Launch(directory: "configured")
    let configured = PlatformSession(launch: launch, directory: "fallback")
    #expect(configured.launch.directory == "configured")
  }

  @Test(arguments: [";2f62696e2f78;", ";2f62696e2f78;;"])
  internal func empty(_ payload: String) throws {
    var launch = Debuggee.Launch()
    try launch.run(payload.utf8Span.span)
    #expect(launch.executable == "/bin/x")
    #expect(launch.arguments == (payload.hasSuffix(";;") ? ["", ""] : [""]))
  }

  @Test(arguments: ["", ";", ";;78"])
  internal func inherited(_ payload: String) throws {
    var launch = Debuggee.Launch(executable: "/old", arguments: ["old"])
    try launch.run(payload.utf8Span.span)
    #expect(launch.executable == "/old")
    #expect(launch.arguments == (payload == ";;78" ? ["x"] : []))
  }

  @Test(arguments: ["invalid", ";2f62696e2f78;zz", ";2f62696e2f78;0",
                    ";2f62696e002f78", ";2f62696e2f78;610062"])
  internal func transaction(_ payload: String) {
    var launch = Debuggee.Launch(executable: "/old", arguments: ["old"])
    #expect(throws: GDBHandlerError.self) {
      try launch.run(payload.utf8Span.span)
    }
    #expect(launch.executable == "/old")
    #expect(launch.arguments == ["old"])
  }

  @Test(arguments: ["", ";", ";;78"])
  internal func missing(_ payload: String) {
    var launch = Debuggee.Launch(arguments: ["old"])
    #expect(throws: GDBHandlerError.self) {
      try launch.run(payload.utf8Span.span)
    }
    #expect(launch.executable == nil)
    #expect(launch.arguments == ["old"])
  }
}

@Suite
internal struct StopRefinementTests {
  @Test
  internal func metadata() {
    let thread =
        ProcessThreadIdentifier(process: ProcessIdentifier(rawValue: 7),
                                thread: ThreadIdentifier(rawValue: 9))
    let fault = Debuggee.Fault(address: Debuggee.Address(rawValue: 42), code: 3,
                               domain: .posix)
    let stop = Debuggee.Stop(thread: thread, reason: .breakpoint, core: 2,
                             fault: fault, child: thread, snapshot: 19,
                             chance: .second)
    let refined = stop.refined(reason: .trace, fault: nil, breakpoint: nil)
    #expect(refined.thread == stop.thread)
    #expect(refined.reason == .trace)
    #expect(refined.core == stop.core)
    #expect(refined.child == stop.child)
    #expect(refined.snapshot == stop.snapshot)
    #expect(refined.chance == stop.chance)
    #expect(refined.fault == nil)
    #expect(refined.breakpoint == nil)
  }
}
