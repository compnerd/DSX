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

  internal let process: pid_t
  private var reader: CInt

  internal init(_ executable: String, arguments: borrowing Span<String>,
                errors: Bool) throws(Debuggee.Error) {
    let descriptors = try UnixDescriptors()
    process = try UnixSpawnActions.run { actions throws(Failure) in
      var status =
          posix_spawn_file_actions_adddup2(&actions, descriptors.writer,
                                           STDOUT_FILENO)
      guard status == 0 else {
        throw UnixProcess.failure(status)
      }
      if errors {
        status = posix_spawn_file_actions_adddup2(&actions, descriptors.writer,
                                                  STDERR_FILENO)
        guard status == 0 else {
          throw UnixProcess.failure(status)
        }
      }
      status = posix_spawn_file_actions_addclose(&actions, descriptors.reader)
      guard status == 0 else {
        throw UnixProcess.failure(status)
      }
      status = posix_spawn_file_actions_addclose(&actions, descriptors.writer)
      guard status == 0 else {
        throw UnixProcess.failure(status)
      }
      return try UnixProcess.spawn(executable, arguments: arguments,
                                   actions: &actions)
    }
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

  internal borrowing func byte() throws(Debuggee.Error) -> UInt8 {
    while true {
      var byte: UInt8 = 0
      let count = DSX::read(reader, &byte, 1)
      if count == 1 {
        return byte
      }
      if count == 0 {
        throw .state
      }
      guard errno == EINTR else {
        throw UnixProcess.failure(errno)
      }
    }
  }

  internal borrowing func prepare() throws(Debuggee.Error) {
    let flags = fcntl(reader, F_GETFL)
    guard flags >= 0, fcntl(reader, F_SETFL, flags | O_NONBLOCK) == 0 else {
      throw UnixProcess.failure(errno)
    }
  }

  internal borrowing func status(_ timeout: Int32) throws(Debuggee.Error)
      -> Debuggee.Exit? {
    var status: CInt = 0
    let waited = waitpid(process, &status, WNOHANG)
    if waited == process {
      return UnixWaitStatus.exit(status) ?? .signalled(0)
    }
    guard waited == 0 || errno == EINTR else {
      throw UnixProcess.failure(errno)
    }
    if timeout > 0 {
      _ = usleep(useconds_t(timeout) * 1_000)
    }
    return nil
  }

  internal borrowing func terminate() throws(Debuggee.Error) {
    kill()
  }

  internal borrowing func kill() {
    _ = DSX::kill(process, SIGKILL)
    while waitpid(process, nil, 0) < 0 && errno == EINTR {
    }
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
      throw failure(errno)
    }
    while waitpid(process, &status, 0) < 0 {
      guard errno == EINTR else {
        throw failure(errno)
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
      throw failure(errno)
    }
  }

  internal static func failure(_ code: CInt) -> Debuggee.Error {
    UnixError.debuggee(code, invalid: .process, support: true)
  }

  private static func spawn(_ executable: String,
                            arguments: borrowing Span<String>,
                            actions: UnsafePointer<UnixSpawnFileActions>?)
      throws(Debuggee.Error) -> pid_t {
    let empty = Span<Debuggee.Environment>()
    return try UnixSpawn.run(arguments, env: empty,
                             prefix: executable) { argv, envp throws(Failure) in
      var process: pid_t = 0
      let status = executable.withCString { executable in
        DSX::posix_spawnp(&process, executable, actions, argv, envp)
      }
      guard status == 0 else {
        throw failure(status)
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
      default: throw UnixProcess.failure(errno)
      }
    }
  }
}
#endif
