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

  internal static var shell: String {
#if os(Android)
    "/system/bin/sh"
#else
    "/bin/sh"
#endif
  }

  internal static var directory: String? {
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
    let identifier = child.process.rawValue
    DSX.log("spawned child \(identifier); awaiting port", level: .trace,
            channel: .process)
    let result = try HostProcess(consume child)
    let process = result.information.process.rawValue
    let port = result.information.port
    DSX.log("child \(process) listening on port \(port)", level: .trace,
            channel: .process)
    return result
  }

  internal static func spawn(_ config: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> HostProcess {
    guard let path = config.executable else {
      throw .process
    }
    var actions = try UnixSpawnActions()
    try actions.configure(config)
    let command = try UnixCommand(config.arguments.span,
                                  env: config.environment.span, prefix: path)
    let process = try command.spawn { argv, envp throws(Failure) in
      var process: pid_t = 0
      let status = path.withCString { path in
        DSX::posix_spawnp(&process, path, &actions.value, argv, envp)
      }
      guard status == 0 else {
        throw Debuggee.Error(unix: status, invalid: .process, support: true)
      }
      return process
    }
    let identifier = ProcessIdentifier(rawValue: UInt64(process))
    return HostProcess(process: identifier, port: 0)
  }

  internal static func execute(_ command: String, directory: String?,
                               timeout: UInt64,
                               into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) -> Debuggee.ProgramStatus {
    let arguments = ["-c", command]
    let child: UnixProcess
    do {
      child = try UnixProcess(shell, arguments: arguments.span, errors: true,
                              directory: directory)
    } catch .unsupported {
      // Older Android and BSD spawn APIs cannot set the child's directory.
      guard let directory else {
        throw .unsupported
      }
      // Pass data as positional arguments, not shell source. Prefix relative
      // paths so that cd cannot interpret a leading '-' as an option or OLDPWD.
      let path = directory.isEmpty || directory.hasPrefix("/")
          ? directory : "./\(directory)"
      let arguments = ["-c", "cd \"$1\" && exec \"$0\" -c \"$2\"", shell,
                       path, command]
      child = try UnixProcess(shell, arguments: arguments.span, errors: true)
    }
    return try child.wait(timeout: timeout, into: &output)
  }

  internal static func user(_ identifier: UInt64) throws(Debuggee.Error)
      -> String {
    guard let identifier = uid_t(exactly: identifier) else {
      throw .process
    }
    return try account { buffer throws(Debuggee.Error) in
      guard let base = buffer.baseAddress else {
        throw .system(ENOMEM)
      }
      var record = passwd()
      var entry: UnsafeMutablePointer<passwd>?
      let status = getpwuid_r(identifier, &record, base, buffer.count, &entry)
      if status == ERANGE {
        return nil
      }
      guard status == 0 else {
        throw Debuggee.Error(process: status)
      }
      guard let entry, let name = entry.pointee.pw_name else {
        throw .process
      }
      return String(cString: name)
    }
  }

  internal static func group(_ identifier: UInt64) throws(Debuggee.Error)
      -> String {
    guard let identifier = gid_t(exactly: identifier) else {
      throw .process
    }
    return try account { buffer throws(Debuggee.Error) in
      guard let base = buffer.baseAddress else {
        throw .system(ENOMEM)
      }
      var record = UnixGroup()
      var entry: UnsafeMutablePointer<group>?
      let status = getgrgid_r(identifier, &record, base, buffer.count, &entry)
      if status == ERANGE {
        return nil
      }
      guard status == 0 else {
        throw Debuggee.Error(process: status)
      }
      guard let entry, let name = entry.pointee.gr_name else {
        throw .process
      }
      return String(cString: name)
    }
  }
}

private typealias UnixGroup = group
private typealias AccountLookup =
    (inout UnsafeMutableBufferPointer<CChar>) throws(Debuggee.Error) -> String?

private func account(_ lookup: AccountLookup) throws(Debuggee.Error) -> String {
  var capacity = 1024
  while true {
    var buffer = Array<CChar>(repeating: 0, count: capacity)
    if let name = try buffer.withUnsafeMutableBufferPointer(lookup) {
      return name
    }
    guard capacity <= Int.max / 2 else {
      throw .system(ENOMEM)
    }
    capacity *= 2
  }
}

#endif
