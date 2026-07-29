// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private import DSX
private import DSXArguments

@main
private struct DebugServerX {
  private static let usage = "dsx <subcommand>"
  private static let help = """
      OVERVIEW: GDB Serial Protocol speaking remote debugging stub

      USAGE: dsx <subcommand>

      OPTIONS:
        -h, --help              Show help information.

      SUBCOMMANDS:
        gdbserver, g            Run using the GDB remote protocol.
        platform, p             Run as an LLDB platform server.
        version, v              Print version information.

        See 'dsx help <subcommand>' for detailed help.
      """
  private static let version = """
      OVERVIEW: Print version information.

      USAGE: dsx version

      OPTIONS:
        -h, --help              Show help information.
      """

  private init() {
  }

  internal static func main() {
    do {
      try DSX.initialize()
    } catch {
      failure(error.description, status: 1)
    }
    execute(CommandLine.arguments)
  }

  private static func execute(_ values: consuming Array<String>) {
    guard values.count > 1 else {
      return output(help)
    }
    let command = values[1]
    var arguments = consume values
    arguments.removeFirst(2)
    switch command {
    case "-h", "--help":
      guard arguments.isEmpty else {
        failure("Unexpected argument '\(arguments[0])'", usage: usage,
                status: 64)
      }
      return output(help)
    case "help":
      return assistance(arguments)
    case "g", "gdbserver":
      return gdbserver(arguments)
    case "p", "platform":
      return platform(arguments)
    case "v", "version":
      return release(arguments)
    default:
      failure("Unexpected argument '\(command)'", usage: usage, status: 64)
    }
  }

  private static func assistance(_ values: borrowing Array<String>) {
    guard values.count <= 1 else {
      failure("Unexpected argument '\(values[1])'", usage: usage, status: 64)
    }
    switch values.first {
    case nil:
      return output(help)
    case "g"?, "gdbserver"?:
      return output(GDBServerCommand.help)
    case "p"?, "platform"?:
      return output(PlatformServerCommand.help)
    case "v"?, "version"?:
      return output(version)
    case let value?:
      failure("Unexpected argument '\(value)'", usage: usage, status: 64)
    }
  }

  private static func gdbserver(_ values: consuming Array<String>) {
    var command: GDBServerCommand
    do {
      command = try GDBServerCommand.parse(values)
    } catch {
      switch error {
      case .help:
        return output(GDBServerCommand.help)
      case .failure(let message):
        failure(message, usage: GDBServerCommand.usage, status: 64)
      }
    }
    do {
      try command.run()
    } catch {
      failure(error.description, status: 1)
    }
  }

  private static func platform(_ values: consuming Array<String>) {
    var command: PlatformServerCommand
    do {
      command = try PlatformServerCommand.parse(values)
    } catch {
      switch error {
      case .help:
        return output(PlatformServerCommand.help)
      case .failure(let message):
        failure(message, usage: PlatformServerCommand.usage, status: 64)
      }
    }
    do {
      try command.run()
    } catch {
      failure(error.description, status: 1)
    }
  }

  private static func release(_ values: borrowing Array<String>) {
    var command: Version
    do {
      command = try Version.parse(values)
    } catch {
      switch error {
      case .help:
        return output(version)
      case .failure(let message):
        failure(message, usage: "dsx version", status: 64)
      }
    }
    command.run()
  }

  private static func failure(_ message: String, usage: String? = nil,
                              status: CInt) -> Never {
    output("Error: \(message)", error: true)
    if let usage {
      output("Usage: \(usage)", error: true)
      output("  See 'dsx --help' for more information.", error: true)
    }
    terminate(status)
  }
}
