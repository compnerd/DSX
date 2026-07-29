// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct Server: ~Copyable, Sendable {
  internal let compatibility: CompatibilityMode
  private let notification: PortNotification?
  private var connection: Connection?
  internal private(set) var endpoint: ConnectionEndpoint?

  internal var bound: UInt16? {
    borrowing get {
      switch endpoint {
      case .none: nil
      case .some(let endpoint): endpoint.bound
      }
    }
  }

  internal init(connection: consuming Connection,
                compatibility: CompatibilityMode,
                notification: consuming PortNotification?) {
    self.compatibility = compatibility
    self.notification = consume notification
    self.connection = consume connection
  }

  @inline(never)
  internal mutating func start() throws(ServerError) {
    guard endpoint == nil else {
      throw .state
    }
    guard let connection = connection.take() else {
      throw .state
    }
    do throws(TransportError) {
      endpoint = try ConnectionEndpoint(consume connection)
      DSX.log("server endpoint established", level: .trace, channel: .transport)
      if let notification {
        try PortNotifier.write(endpoint?.bound, to: notification)
      }
    } catch {
      throw .transport(error)
    }
  }

  internal mutating func accept() throws(ServerError) -> ConnectionTransport {
    guard case .some(let current) = endpoint.take() else {
      throw .state
    }
    var accepted: ConnectionAcceptance
    do throws(TransportError) {
      accepted = try current.accept()
      DSX.log("client accepted", level: .trace, channel: .transport)
    } catch {
      throw .transport(error)
    }
    if let listener = accepted.listener.take() {
      endpoint = .listener(consume listener)
    }
    return consume accepted.transport
  }

  internal mutating func start(daemonize: Bool) throws(ServerError) -> Bool {
    if daemonize, Host.daemonization == .before {
      guard try detach() else {
        return false
      }
    }
    try start()
    if daemonize, Host.daemonization == .after {
      return try detach()
    }
    return true
  }
}

@inline(never)
private func detach() throws(ServerError) -> Bool {
  do throws(DaemonizationError) {
    return try Host.daemonize()
  } catch {
    throw .daemon(error)
  }
}
