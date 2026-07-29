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
internal import DSXShims

/// Tracks a process launched by DSX and owns its output descriptor.
internal struct UnixProcess: ~Copyable {
  private typealias Failure = Debuggee.Error

  private let identifier: pid_t
  private var reader: CInt

  internal var process: ProcessIdentifier {
    ProcessIdentifier(rawValue: UInt64(identifier))
  }

  internal init(_ executable: String, arguments: borrowing Span<String>,
                errors: Bool, directory: String? = nil) throws(Debuggee.Error) {
    let descriptors = try UnixDescriptors()
    let flags = fcntl(descriptors.reader, F_GETFL)
    guard flags >= 0 else {
      throw Debuggee.Error(process: errno)
    }
    guard fcntl(descriptors.reader, F_SETFL, flags | O_NONBLOCK) == 0 else {
      throw Debuggee.Error(process: errno)
    }
    var actions = try UnixSpawnActions()
    try actions.configure(Debuggee.Launch(directory: directory))
    try actions.duplicate(descriptors.writer, to: STDOUT_FILENO,
                          failure: Debuggee.Error.init(process:))
    if errors {
      try actions.duplicate(descriptors.writer, to: STDERR_FILENO,
                            failure: Debuggee.Error.init(process:))
    }
    try actions.close(descriptors.reader, failure: Debuggee.Error.init(process:))
    try actions.close(descriptors.writer, failure: Debuggee.Error.init(process:))
    identifier = try UnixProcess.spawn(executable, arguments: arguments,
                                       actions: &actions.value)
    reader = descriptors.release()
  }

  deinit {
    if reader >= 0 {
      _ = DSX::close(reader)
    }
  }

  internal consuming func monitor() -> WaitHandle {
    let descriptor = reader
    reader = -1
    return WaitHandle(descriptor)
  }

  internal borrowing func byte(timeout: Int32) throws(Debuggee.Error)
      -> UInt8? {
    do {
      let event = try WaitHandle(reader).wait(timeout: timeout, events: Span())
      if event == .timeout {
        return nil
      }
    } catch .read(let code) {
      throw Debuggee.Error(process: code)
    } catch {
      throw .state
    }
    while true {
      var byte: UInt8 = 0
      let count = DSX::read(reader, &byte, 1)
      if count == 1 {
        return byte
      }
      if count == 0 {
        throw .state
      }
      if errno == EAGAIN || errno == EWOULDBLOCK {
        return nil
      }
      guard errno == EINTR else {
        throw Debuggee.Error(process: errno)
      }
    }
  }

  internal borrowing func status(timeout: Int32) throws(Debuggee.Error)
      -> Debuggee.Exit? {
    var status: CInt = 0
    let waited = waitpid(identifier, &status, WNOHANG)
    switch waited {
    case identifier:
      return UnixWaitStatus(status).exit ?? .signalled(0)
    case 0:
      break
    default:
      guard errno == EINTR else {
        throw Debuggee.Error(process: errno)
      }
    }
    if timeout > 0 {
      _ = usleep(useconds_t(timeout) * 1_000)
    }
    return nil
  }

  internal borrowing func terminate() throws(Debuggee.Error) {
    try UnixProcess.terminate(process)
  }

  internal static func terminate(_ identifier: ProcessIdentifier)
      throws(Debuggee.Error) {
    if try reap(identifier) {
      return
    }
    guard identifier.rawValue <= UInt64(pid_t.max) else {
      throw .process
    }
    let process = pid_t(identifier.rawValue)
    var status: CInt = 0
    guard DSX::kill(process, SIGKILL) == 0 else {
      if errno == ESRCH, try reap(identifier) {
        return
      }
      throw Debuggee.Error(process: errno)
    }
    while waitpid(process, &status, 0) < 0 {
      guard errno == EINTR else {
        throw Debuggee.Error(process: errno)
      }
    }
  }

  internal static func reap(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Bool {
    guard process.rawValue <= UInt64(pid_t.max) else {
      throw .process
    }
    let process = pid_t(process.rawValue)
    while true {
      let waited = waitpid(process, nil, WNOHANG)
      if waited == process {
        return true
      }
      if waited == 0 {
        return false
      }
      if errno == EINTR {
        continue
      }
      if errno == ECHILD {
        return true
      }
      throw Debuggee.Error(process: errno)
    }
  }

  private static func spawn(_ executable: String,
                            arguments: borrowing Span<String>,
                            actions: UnsafePointer<UnixSpawnFileActions>?)
      throws(Debuggee.Error) -> pid_t {
    let empty = Span<Debuggee.Environment>()
    let command = try UnixCommand(arguments, env: empty, prefix: executable)
    return try command.spawn { argv, envp throws(Failure) in
      var process: pid_t = 0
      let status = executable.withCString { executable in
        DSX::posix_spawnp(&process, executable, actions, argv, envp)
      }
      guard status == 0 else {
        throw Debuggee.Error(process: status)
      }
      return process
    }
  }

  internal borrowing func read(_ buffer: UnsafeMutableBufferPointer<UInt8>)
      throws(Debuggee.Error) -> Int {
    while true {
      let count = DSX::read(reader, buffer.baseAddress, buffer.count)
      if count >= 0 {
        return count
      }
      switch errno {
      case EINTR: continue
      case EAGAIN, EWOULDBLOCK: return 0
      default: throw Debuggee.Error(process: errno)
      }
    }
  }
}
#endif
