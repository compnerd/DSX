// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import DSX
internal import DSXArguments

internal struct GDBServerCommand {
  internal static let usage =
      "dsx g[dbserver] [options] [[host]:port] [[--] program args...]"
  internal static let help = """
      OVERVIEW: Run using the GDB remote protocol.

      USAGE: dsx g[dbserver] [options] [[host]:port] [[--] program args...]

      ARGUMENTS:
        <inputs>

      OPTIONS:
        --fd <fd>               Communicate over the given file descriptor.
        --device <device>       Communicate over the given character device.
        --connection-pipe <connection-pipe>
                                Communicate over the given named pipe.
        --named-pipe <named-pipe>
                                Write the listening port to the given \
      named pipe.
        --pipe <pipe>           Write the listening port to the given \
      file descriptor.
        --reverse-connect       Connect to the client instead of listening.
        --log-channels <log-channels>
                                Channels and categories to log.
        --log-file <log-file>   Destination file for logs.
        -S, --setsid            Run in a new session.
        --daemonize             Detach and run as a daemon.
        --attach <attach>       Attach to a process identifier or name.
        -h, --help              Show help information.
      """

  internal var fd: CInt?
  internal var device: String?
  internal var channel: String?
  internal var named: String?
  internal var pipe: CInt?
  internal var reverse = false
  internal var channels: String?
  internal var log: String?
  internal var setsid = false
  internal var daemonize = false
  internal var attach: String?
  internal var registers = false
  internal var inputs = Array<String>()

  internal init() {
  }

  internal static func parse(_ values: consuming Array<String>)
      throws(ArgumentError) -> GDBServerCommand {
    var command = GDBServerCommand()
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
      case "--fd":
        let value = try arguments.value(option)
        guard let descriptor = CInt(value) else {
          throw .failure("Invalid value '\(value)' for '--fd'")
        }
        command.fd = descriptor
      case "--device":
        command.device = try arguments.value(option)
      case "--connection-pipe":
        command.channel = try arguments.value(option)
      case "--named-pipe":
        command.named = try arguments.value(option)
      case "--pipe":
        let value = try arguments.value(option)
        guard let descriptor = CInt(value) else {
          throw .failure("Invalid value '\(value)' for '--pipe'")
        }
        command.pipe = descriptor
      case "--reverse-connect":
        try arguments.flag(option)
        command.reverse = true
      case "--log-channels":
        command.channels = try arguments.value(option)
      case "--log-file":
        command.log = try arguments.value(option)
      case "-S", "--setsid":
        try arguments.flag(option)
        command.setsid = true
      case "--daemonize":
        try arguments.flag(option)
        command.daemonize = true
      case "--attach":
        command.attach = try arguments.value(option)
      case "--native-regs":
        try arguments.flag(option)
        command.registers = true
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
      throws(CommandConfigurationError) {
    let named = path()
    if case (_?, _?) = (pipe, named) {
      throw .notifications
    }
    if let pipe, pipe < 0 {
      throw .descriptor
    }
    if let named {
      guard !named.isEmpty else {
        throw .location
      }
    }
    if let attach {
      guard !attach.isEmpty else {
        throw .attach
      }
      if launching {
        throw .debuggee
      }
    }
    switch (pipe, named) {
    case (_?, nil), (nil, _?):
      guard case .network(_, _, let reverse) = connection else {
        throw .notification
      }
      if reverse {
        throw .notification
      }
    default:
      break
    }
  }

  internal func resolve() throws(DSX.Error) -> Connection {
    switch (fd, device, channel) {
    case (_?, _?, _), (_?, _, _?), (_, _?, _?):
      throw .failure("multiple connection transports")
    default:
      break
    }
    if let fd, fd < 0 {
      throw .failure("invalid file descriptor")
    }
    if let device, device.isEmpty {
      throw .failure("invalid connection location")
    }
    if let channel, channel.isEmpty {
      throw .failure("invalid connection location")
    }

    return switch (fd, device, channel, inputs.first) {
    case let (fd?, _, _, _): .descriptor(fd)
    case let (_, device?, _, _): .device(device)
    case let (_, _, channel?, _): .pipe(channel)
    case let (_, _, _, location?):
      try Connection.parse(location, reverse: reverse)
    case (_, _, _, nil):
      throw .failure("no connection arguments")
    }
  }

  internal consuming func program() -> Array<String> {
    var arguments = inputs
    switch (fd, device, channel) {
    case (nil, nil, nil):
      arguments.removeFirst()
      if case .none = named,
          let index = arguments.firstIndex(of: "--named-pipe") {
        guard index + 1 < arguments.count else {
          return arguments
        }
        arguments.removeSubrange(index ... (index + 1))
      }
    default:
      break
    }
    return arguments
  }

  internal consuming func debuggee() -> GDBServerDebuggee? {
    if let attach {
      return .attach(attach)
    }
    var arguments = program()
    guard let executable = arguments.first else {
      return nil
    }
    arguments.removeFirst()
    return .launch(executable, arguments)
  }

  internal func notification() -> PortNotification? {
    let named = path()
    return switch (pipe, named) {
    case let (descriptor?, nil): .descriptor(descriptor)
    case let (nil, path?): .pipe(path)
    default: nil
    }
  }

  private func path() -> String? {
    if let named {
      return named
    }
    guard case (nil, nil, nil) = (fd, device, channel),
        let index = inputs.firstIndex(of: "--named-pipe"),
        index + 1 < inputs.count else {
      return nil
    }
    return inputs[index + 1]
  }

  private var launching: Bool {
    switch (fd, device, channel) {
    case (nil, nil, nil):
      var count = inputs.count - 1
      if case .none = named, let index = inputs.firstIndex(of: "--named-pipe"),
          index + 1 < inputs.count {
        count -= 2
      }
      return count > 0
    default:
      return inputs.isEmpty == false
    }
  }

  internal consuming func run() throws(DSX.Error) {
    let connection = try resolve()
    // `--native-regs` is intentionally a no-op. DSX always uses its generated
    // native register model.
    _ = registers
    let notification = notification()
    let channels = channels
    let log = log
    let setsid = setsid
    let daemonize = daemonize
    let configuration =
        DSX.Configuration.lldb(connection, debuggee: debuggee(),
                               notification: notification)
    try DSX.run(configuration, logging: channels, to: log, isolate: setsid,
                daemonize: daemonize)
  }
}

internal enum CommandConfigurationError: Error, CustomStringConvertible {
  case attach
  case descriptor
  case location
  case notification
  case notifications
  case debuggee

  internal var description: String {
    switch self {
    case .attach: "attached debuggee must not be empty"
    case .descriptor: "port notification descriptor must be nonnegative"
    case .location: "port notification path must not be empty"
    case .notification:
      "port notification requires a listening network connection"
    case .notifications:
      "--pipe and --named-pipe are mutually exclusive"
    case .debuggee:
      "--attach and a program launch are mutually exclusive"
    }
  }
}
