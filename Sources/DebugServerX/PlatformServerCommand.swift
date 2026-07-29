// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import DSX
internal import DSXArguments

internal struct PlatformServerCommand {
  internal static let usage = "dsx p[latform] [options] --listen <[host]:port>"
  internal static let help = """
      OVERVIEW: Run as an LLDB platform server.

      USAGE: dsx p[latform] [options] --listen <[host]:port>

      ARGUMENTS:
        <inputs>

      OPTIONS:
        -L, --listen <listen>   Host and port on which to listen.
        -f, --socket-file <socket-file>
                                Write listening socket information to this file.
        -P, --gdbserver-port <gdbserver-port>
                                Port for spawned gdbserver instances.
        --server                Accept multiple client connections sequentially.
        -c, --log-channels <log-channels>
                                Channels and categories to log.
        -l, --log-file <log-file>
                                Destination file for logs.
        --daemonize             Detach and run as a daemon.
        -h, --help              Show help information.
      """

  internal var listen: String?
  internal var socket: String?
  internal var port: UInt16?
  internal var child: CInt?
  internal var server = false
  internal var channels: String?
  internal var log: String?
  internal var daemonize = false
  internal var debug = false
  internal var verbose = false
  internal var inputs = Array<String>()

  internal init() {
  }

  internal static func parse(_ values: consuming Array<String>)
      throws(ArgumentError) -> PlatformServerCommand {
    var command = PlatformServerCommand()
    var arguments = Arguments(values)
    while let argument = arguments.next() {
      if argument == "--" {
        command.inputs = arguments.remaining()
        break
      }
      if argument == "-" {
        command.inputs = arguments.remainder()
        break
      }
      guard argument.hasPrefix("-") else {
        command.inputs = arguments.remainder()
        break
      }

      let option = arguments.option(argument)
      switch option.name {
      case "-L", "--listen":
        command.listen = try arguments.value(option)
      case "-f", "--socket-file":
        command.socket = try arguments.value(option)
      case "-P", "--gdbserver-port":
        let value = try arguments.value(option)
        guard let port = UInt16(value) else {
          throw .failure("Invalid value '\(value)' for '--gdbserver-port'")
        }
        command.port = port
      case "--child-platform-fd":
        let value = try arguments.value(option)
        guard let descriptor = CInt(value) else {
          throw .failure("Invalid value '\(value)' for '--child-platform-fd'")
        }
        command.child = descriptor
      case "--server":
        try arguments.flag(option)
        command.server = true
      case "-c", "--log-channels":
        command.channels = try arguments.value(option)
      case "-l", "--log-file":
        command.log = try arguments.value(option)
      case "--daemonize":
        try arguments.flag(option)
        command.daemonize = true
      case "--debug":
        try arguments.flag(option)
        command.debug = true
      case "--verbose":
        try arguments.flag(option)
        command.verbose = true
      case "-h", "--help":
        try arguments.flag(option)
        throw .help
      default:
        throw .failure("Unknown option '\(option.name)'")
      }
    }
    try command.validate()
    return command
  }

  internal func validate() throws(ArgumentError) {
    let connection: Connection
    do {
      connection = try resolve()
    } catch {
      throw .failure(error.description)
    }
    do {
      try check(connection)
    } catch {
      throw .failure(error.description)
    }
  }

  internal func check(_ connection: consuming Connection)
      throws(PlatformConfigurationError) {
    if let socket {
      guard !socket.isEmpty else {
        throw .socket
      }
      guard case .network(_, _, let reverse) = connection else {
        throw .notification
      }
      if reverse {
        throw .notification
      }
    }
    guard inputs.isEmpty else {
      throw .arguments
    }
  }

  internal func resolve() throws(DSX.Error) -> Connection {
    switch (listen, child) {
    case let (listen?, nil): try Connection.parse(listen)
    case let (nil, child?) where child >= 0: .descriptor(child)
    case (nil, nil):
      throw .failure("no connection arguments")
    default:
      throw .failure("multiple connection transports")
    }
  }

  internal consuming func run() throws(DSX.Error) {
    let connection = try resolve()
    let notification = socket.map(PortNotification.file)
    let configuration =
        DSX.Configuration.platform(connection, multiple: server, port: port,
                                   executable: CommandLine.arguments[0],
                                   notification: notification)
    try DSX.run(configuration, logging: selection(), to: log,
                daemonize: daemonize)
  }

  internal func selection() -> String? {
    if let channels {
      return channels
    }
    return switch (debug, verbose) {
    case (_, true): "all:trace"
    case (true, false): "gdb-remote packets:debug"
    case (false, false): nil
    }
  }
}

internal enum PlatformConfigurationError: Error, CustomStringConvertible {
  case arguments
  case notification
  case socket

  internal var description: String {
    switch self {
    case .arguments: "platform mode does not accept positional arguments"
    case .notification:
      "--socket-file requires a listening network connection"
    case .socket: "socket file path must not be empty"
    }
  }
}
