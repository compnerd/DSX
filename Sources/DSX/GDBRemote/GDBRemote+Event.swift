// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBRemote where Channel: ~Copyable {
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
    if lifecycle, case .started(let thread) = event {
      let stop = Debuggee.Stop(thread: thread, reason: .create)
      session.debuggee.observe(.stopped(stop), global: false)
      core.state.selection.stopped = thread
    }
    if core.state.nonstop, event.completion || lifecycle {
      let capacity = core.state.negotiation.payload
      if case .extended = termination {
        try core.channel.respond(capacity, encoding: .text,
                                 { writer throws(GDBHandlerError) in
          try writer.append("OK")
        })
        return try core.channel.send()
      }
      let pending = core.state.stops.first != nil
      do {
        try session.record(event, state: &core.state)
      } catch {
        throw .handler(error)
      }
      guard pending == false, let reply = core.state.stops.first else {
        return
      }
      try core.channel.respond(capacity, encoding: .text,
                               { writer throws(GDBHandlerError) in
        try writer.append("Stop:")
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
