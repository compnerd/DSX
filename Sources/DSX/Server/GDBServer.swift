// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBServer: ~Copyable, Sendable {
  private var server: Server
  private let initial: DSX.Debuggee?

  internal var bound: UInt16? {
    borrowing get { server.bound }
  }

  internal init(connection: consuming Connection,
                compatibility: CompatibilityMode = .gdb,
                debuggee: consuming DSX.Debuggee? = nil,
                notification: consuming PortNotification? = nil) {
    server = Server(connection: consume connection,
                    compatibility: compatibility,
                    notification: consume notification)
    initial = consume debuggee
  }

  internal mutating func start() throws(ServerError) {
    try server.start()
  }

  internal mutating func accept() throws(ServerError)
      -> GDBRemote<ConnectionTransport> {
    DSX.log("waiting for client", level: .trace, channel: .transport)
    if let interval = NativeDebugControl.interval {
      while try wait(interval) != .channel {
      }
    }
    let transport = try server.accept()
    let session: DebugSession
    do throws(Debuggee.Error) {
      session = try DebugSession(initial)
    } catch {
      throw .debuggee(error)
    }
    return GDBRemote(channel: consume transport, session: consume session,
                     compatibility: server.compatibility)
  }

  private borrowing func wait(_ timeout: Int32) throws(ServerError)
      -> WaitResult {
    switch server.endpoint {
    case .some(let endpoint):
      do throws(TransportError) {
        return try endpoint.wait(timeout, events: Span())
      } catch {
        throw .transport(error)
      }
    case .none: throw .state
    }
  }

  @inline(never)
  internal mutating func run(daemonize: Bool = false) throws(ServerError) {
    guard try server.start(daemonize: daemonize) else {
      return
    }
    var remote = try accept()
    try remote.serve()
  }
}

extension GDBRemote where Channel: ~Copyable {
  @inline(never)
  internal mutating func serve() throws(ServerError) {
    var closure = SessionClosure.failure
    defer {
      DSX.log("closing client session", level: .trace, channel: .remote)
      close(closure)
    }
    while true {
      if complete {
        closure = .normal
        return
      }
      do throws(GDBRemoteError) {
        try step()
      } catch .closed {
        return DSX.log("client disconnected", level: .trace, channel: .remote)
      } catch .transport(let error) {
        throw .transport(error)
      } catch {
        throw .session
      }
    }
  }
}
