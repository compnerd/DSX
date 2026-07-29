// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

public enum DSX {
  public enum Configuration: Sendable {
    case gdb(Connection, debuggee: Debuggee?, notification: Notification?)
    case lldb(Connection, debuggee: Debuggee?, notification: Notification?)
    case platform(Connection, multiple: Bool, port: UInt16?,
                  executable: String?, notification: Notification?)
  }

  public enum Error: Swift.Error, Sendable {
    case failure(String)
  }

  public static func initialize() throws(DSX.Error) {
    if let failure = Host.initialize() {
      throw .failure(failure)
    }
    _ = enabled(.off, channel: .system)
  }

  public static func run(_ configuration: consuming Configuration,
                         logging channels: borrowing String? = nil,
                         to file: borrowing String? = nil,
                         isolate: Bool = false,
                         daemonize: Bool = false) throws(DSX.Error) {
    if isolate {
      do throws(SessionIsolationError) {
        try Host.isolate()
      } catch {
        throw .failure(error.description)
      }
    }
    do throws(LogConfigurationError) {
      try logging(channels, to: file)
    } catch {
      throw .failure(error.description)
    }

    do {
      switch consume configuration {
      case .gdb(let connection, let debuggee, let notification):
        var server = GDBServer(connection: connection, compatibility: .gdb,
                               debuggee: debuggee, notification: notification)
        try server.run(daemonize: daemonize)
      case .lldb(let connection, let debuggee, let notification):
        var server = GDBServer(connection: connection, compatibility: .lldb,
                               debuggee: debuggee, notification: notification)
        try server.run(daemonize: daemonize)
      case .platform(let connection, let multiple, let port, let executable,
                     let notification):
        var server = PlatformServer(connection: connection, multiple: multiple,
                                    port: port, executable: executable,
                                    notification: notification,
                                    logging: copy channels)
        try server.run(daemonize: daemonize)
      }
    } catch {
      throw .failure(error.description)
    }
  }
}

extension DSX.Error: CustomStringConvertible {
  public var description: String {
    switch self {
    case .failure(let message): message
    }
  }
}
