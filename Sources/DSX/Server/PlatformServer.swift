// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct PlatformServer: ~Copyable, Sendable {
  private var server: Server
  private var servers = PlatformProcesses()
  private let multiple: Bool
  private let port: UInt16?
  private let executable: String?
  private let logging: String?

  internal var bound: UInt16? {
    borrowing get { server.bound }
  }

  internal init(connection: consuming Connection, multiple: Bool = false,
                port: UInt16? = nil, executable: consuming String? = nil,
                notification: consuming PortNotification? = nil,
                compatibility: CompatibilityMode = .lldb,
                logging: consuming String? = nil) {
    server = Server(connection: consume connection,
                    compatibility: compatibility,
                    notification: consume notification)
    self.multiple = multiple
    self.port = port
    self.executable = consume executable
    self.logging = consume logging
  }

  internal mutating func start() throws(ServerError) {
    try server.start()
  }

  internal mutating func accept() throws(ServerError) -> PlatformRemote {
    DSX.log("waiting for client", level: .trace, channel: .transport)
    while try wait() != .channel {
      servers.reap()
    }
    let transport = try server.accept()
    let session = PlatformSession(port: port, executable: executable,
                                  logging: logging, tracking: servers.take())
    return PlatformRemote(channel: consume transport, session: consume session,
                          compatibility: server.compatibility)
  }

  private borrowing func wait() throws(ServerError) -> WaitResult {
    switch server.endpoint {
    case .some(let endpoint):
      do throws(TransportError) {
        return try servers.wait { timeout, events throws(TransportError) in
          try endpoint.wait(timeout, events: events)
        }
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
    repeat {
      var remote = try accept()
      do {
        defer {
          servers = remote.session.release()
        }
        try remote.serve()
      } catch {
        if multiple {
          DSX.log("client session failed: \(error)", level: .warning,
                  channel: .remote)
          continue
        }
        throw error
      }
    } while multiple
  }
}

extension PlatformRemote {
  @inline(never)
  internal mutating func serve() throws(ServerError) {
    defer {
      DSX.log("closing client session", level: .trace, channel: .remote)
      close()
    }
    while true {
      if complete {
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
