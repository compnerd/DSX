// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct GDBRegisterRequestTests {
  @Test(arguments: [";", "0;", "0;;", ";thread:", "0;thread:;",
                    "0;thread:2;;", "0;other:2"])
  internal func malformed(_ packet: String) {
    let session = DebugSession()
    var state = GDBRemoteSessionState(compatibility: .lldb)
    state.negotiation.enabled.insert(.threadsuffix)
    let payload = Array(packet.utf8)
    #expect(throws: GDBHandlerError.malformed) {
      try GDBRegisterRequest(payload.span, debuggee: session.debuggee,
                             state: state)
    }
  }

  @Test(arguments: ["", "0", ";thread:2", ";thread:2;",
                    "0;thread:p1.2", "0;thread:p1.2;"])
  internal func suffix(_ packet: String) throws {
    let process = ProcessIdentifier(rawValue: 1)
    let thread = ProcessThreadIdentifier(process: process,
                                         thread: ThreadIdentifier(rawValue: 2))
    var session = DebugSession()
    session.debuggee.observe(.started(thread))
    var state = GDBRemoteSessionState(compatibility: .lldb)
    state.negotiation.enabled.insert(.threadsuffix)
    let payload = Array(packet.utf8)
    let request =
        try GDBRegisterRequest(payload.span, debuggee: session.debuggee,
                               state: state)
    #expect(request.thread == thread)
    #expect(request.range.count == (packet.hasPrefix("0") ? 1 : 0))
    state.negotiation.enabled.remove(.threadsuffix)
    let disabled =
        try GDBRegisterRequest(payload.span, debuggee: session.debuggee,
                               state: state)
    #expect(disabled.range.count == payload.count)
  }
}
