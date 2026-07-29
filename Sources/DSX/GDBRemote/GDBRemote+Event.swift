// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemote {
  internal mutating func handle(event incoming: consuming Debuggee.Event)
      throws(GDBRemoteError) {
    func acknowledge(_ writer: inout GDBPacketWriter) throws(GDBHandlerError)
        -> GDBPacketDisposition {
      try writer.append("OK")
      return .reply
    }

    let event = consume incoming
    let requested = if case .terminated(let thread, _) = event {
      core.state.options.contains(thread, option: 0x02)
    } else {
      false
    }
    core.state.observe(event)
    let termination = if case .exited(let process, _) = event {
      core.state.termination.take(process)
    } else {
      GDBRemoteTermination.none
    }
    if let failure = session.failure() {
      return try core.finish(.none, failure: .debuggee(failure))
    }
    let lifecycle = event.lifecycle && (core.state.events || requested)
    let output = if case .output = event { true } else { false }
    if lifecycle, case .started(let thread) = event {
      let stop = Debuggee.Stop(thread: thread, reason: .create)
      session.debuggee.observe(.stopped(stop), global: false)
      core.state.selection.stopped = thread
    }
    let notification = if case .extended = termination {
      false
    } else {
      core.state.nonstop && (event.completion || lifecycle || output)
    }
    if notification {
      let capacity = core.state.negotiation.payload
      let pending = output ? core.state.output.first != nil
                           : core.state.stops.first != nil
      do {
        if case .output(let process) = event {
          try session.record(process, state: &core.state)
        } else {
          try session.record(event, state: &core.state)
        }
      } catch {
        throw .handler(error)
      }
      let reply = output ? core.state.output.first : core.state.stops.first
      guard pending == false, let reply else {
        return
      }
      let prefix: StaticString = output ? "Stdio:" : "Stop:"
      try core.channel.respond(capacity, encoding: .text,
                               { writer throws(GDBHandlerError) in
        try writer.append(prefix)
        try writer.append(reply.span)
      })
      core.channel.notification()
      return try core.channel.send()
    }
    var disposition = GDBPacketDisposition.none
    let capacity = core.state.negotiation.payload
    let result = core.channel.response(capacity, encoding: .text,
                                       { writer throws(GDBHandlerError) in
      let selected = switch termination {
      case .extended: try acknowledge(&writer)
      case .legacy, .none:
        try session.handle(event: event, state: &core.state, writer: &writer)
      }
      disposition = selected
    })
    let failure: GDBHandlerError? = switch result {
    case .failure(let error): error
    case .success: nil
    }

    try core.finish(disposition, failure: failure)
  }
}
