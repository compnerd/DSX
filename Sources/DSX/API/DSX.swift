// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

public enum DSX {
  public static func initialize() throws(DSX.Error) {
    if let failure = Host.initialize() {
      throw .failure(failure)
    }
    _ = enabled(.off, channel: .system)
  }

  public static func run(_ configuration: consuming Configuration,
                         logging channels: borrowing String? = nil,
                         to file: borrowing String? = nil,
                         isolate: Bool = false, daemonize: Bool = false,
                         events: Events = .polling) throws(DSX.Error) {
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
      case let .gdb(connection, debuggee, notification):
        var server = GDBServer(connection: connection, compatibility: .gdb,
                               debuggee: debuggee, notification: notification)
        try server.run(daemonize: daemonize, events: events)
      case let .lldb(connection, debuggee, notification):
        var server = GDBServer(connection: connection, compatibility: .lldb,
                               debuggee: debuggee, notification: notification)
        try server.run(daemonize: daemonize, events: events)
      case let .platform(connection, multiple, port, executable, notification):
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
    case let .failure(message): message
    }
  }
}
