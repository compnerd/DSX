// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

extension Host {
  private typealias Failure = Debuggee.Error

  internal static var working: String? {
    guard let path = getcwd(nil, 0) else {
      return nil
    }
    defer {
      free(path)
    }
    return String(cString: path)
  }

  internal static func launch(_ executable: String,
                              arguments: borrowing Span<String>)
      throws(Debuggee.Error) -> HostProcess {
    let child = try UnixProcess(executable, arguments: arguments, errors: false)
    DSX.log("spawned child \(child.process); awaiting port", level: .trace,
            channel: .process)
    let port: UInt16
    do {
      port = try child.notification()
    } catch {
      child.kill()
      throw error
    }
    DSX.log("child \(child.process) listening on port \(port)", level: .trace,
            channel: .process)
    let identifier = ProcessIdentifier(rawValue: UInt64(child.process))
    let monitor = child.monitor()
    return HostProcess(process: identifier, port: port, monitor: monitor)
  }

  internal static func spawn(_ config: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> HostProcess {
    guard let executable = config.executable else {
      throw .process
    }
    let process = try UnixSpawnActions.run(config) { actions throws(Failure) in
      try UnixSpawn.run(config.arguments.span, env: config.environment.span,
                        prefix: executable) { argv, envp throws(Failure) in
        var process: pid_t = 0
        let status = executable.withCString { executable in
          DSX::posix_spawnp(&process, executable, &actions, argv, envp)
        }
        guard status == 0 else {
          throw UnixError.debuggee(status, invalid: .process, support: true)
        }
        return process
      }
    }
    let identifier = ProcessIdentifier(rawValue: UInt64(process))
    return HostProcess(process: identifier, port: 0)
  }

  internal static func execute(_ command: String, directory working: String?,
                               timeout: UInt64,
                               into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> Debuggee.ProgramStatus {
    let script = if let working {
      "cd \(quote(working)) && \(command)"
    } else {
      command
    }
    let arguments = ["-c", script]
    let child =
        try UnixProcess("/bin/sh", arguments: arguments.span, errors: true)
    return try child.wait(timeout, into: &output)
  }

  internal static func user(_ identifier: UInt64) throws(Debuggee.Error)
      -> String {
    guard identifier <= UInt64(uid_t.max),
        let entry = getpwuid(uid_t(identifier)),
        let name = entry.pointee.pw_name else {
      throw .process
    }
    return String(cString: name)
  }

  internal static func group(_ identifier: UInt64) throws(Debuggee.Error)
      -> String {
    guard identifier <= UInt64(gid_t.max),
        let entry = getgrgid(gid_t(identifier)),
        let name = entry.pointee.gr_name else {
      throw .process
    }
    return String(cString: name)
  }

  private static func quote(_ value: String) -> String {
    "'\(value.replacing("'", with: "'\\''"))'"
  }
}

#endif
