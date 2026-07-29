// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

private typealias Failure = Debuggee.Error

extension DarwinDebugControl {
  internal mutating func launch(_ config: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> ProcessIdentifier {
    guard let executable = config.executable else {
      throw .process
    }
    var attributes: posix_spawnattr_t?
    var status = posix_spawnattr_init(&attributes)
    guard status == 0 else {
      throw UnixDebugProcess.failure(status)
    }
    defer {
      posix_spawnattr_destroy(&attributes)
    }
    var empty = sigset_t()
    var full = sigset_t()
    guard sigemptyset(&empty) == 0, sigfillset(&full) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    status = posix_spawnattr_setsigmask(&attributes, &empty)
    guard status == 0 else {
      throw UnixDebugProcess.failure(status)
    }
    status = posix_spawnattr_setsigdefault(&attributes, &full)
    guard status == 0 else {
      throw UnixDebugProcess.failure(status)
    }
    let flags = POSIX_SPAWN_START_SUSPENDED
              | POSIX_SPAWN_SETPGROUP
              | POSIX_SPAWN_SETSIGDEF
              | POSIX_SPAWN_SETSIGMASK
              | POSIX_SPAWN_CLOEXEC_DEFAULT
              | (config.aslr ? 0 : kPOSIXSpawnDisableASLR)
    status = posix_spawnattr_setflags(&attributes, flags)
    guard status == 0 else {
      throw UnixDebugProcess.failure(status)
    }
    let capture = switch (config.input, config.output, config.error) {
    case (.some, .some, .some): false
    default: true
    }
    var descriptors = UnixDescriptors(reader: -1, writer: -1)
    if capture {
      descriptors = try UnixDescriptors(terminal: config.terminal)
    }
    let process =
        try UnixSpawnActions.run(config) { actions throws(Debuggee.Error) in
      if capture {
        try redirect(config, descriptors: descriptors, actions: &actions)
      }
      return try spawn(executable, arguments: config.arguments.span,
                       environment: config.environment.span, actions: &actions,
                       attributes: &attributes)
    }
    let identifier = ProcessIdentifier(rawValue: UInt64(process))
    let exceptions: DarwinExceptions
    do throws(Debuggee.Error) {
      exceptions = try DarwinExceptions(identifier, ignored: ignored)
    } catch {
      try? UnixProcess.terminate(identifier)
      throw error
    }
    guard ptrace(kPTAttachException, process, nil, 0) == 0 else {
      let code = errno
      try? UnixProcess.terminate(identifier)
      throw UnixDebugProcess.failure(code)
    }
    do throws(Debuggee.Error) {
      try start(process, exceptions: exceptions)
    } catch {
      try? UnixProcess.terminate(identifier)
      throw error
    }
    self.process = identifier
    attached = true
    self.exceptions = exceptions
    if capture {
      reader = descriptors.release()
    }
    return identifier
  }
}

private func start(_ process: pid_t, exceptions: DarwinExceptions)
    throws(Debuggee.Error) {
  var status: CInt = 0
  var waited: pid_t
  repeat {
    waited = waitpid(process, &status, 0)
  } while waited == -1 && errno == EINTR
  guard waited == process, UnixWaitStatus.stopped(status) else {
    throw UnixDebugProcess.failure(errno)
  }
  while true {
    if let record = try exceptions.receive() {
      guard record.type == EXC_SOFTWARE, record.count > 1,
          record.codes.0 == EXC_SOFT_SIGNAL, record.codes.1 == SIGSTOP else {
        throw .state
      }
      break
    }
    _ = usleep(1_000)
  }
}

private func redirect(_ config: borrowing Debuggee.Launch,
                      descriptors: borrowing UnixDescriptors,
                      actions: inout UnixSpawnFileActions)
    throws(Debuggee.Error) {
  for (path, descriptor) in [
    (config.input, STDIN_FILENO),
    (config.output, STDOUT_FILENO),
    (config.error, STDERR_FILENO),
  ] where path == nil {
    let status =
        posix_spawn_file_actions_adddup2(&actions, descriptors.writer,
                                         descriptor)
    guard status == 0 else {
      throw UnixDebugProcess.failure(status)
    }
  }
  var status = posix_spawn_file_actions_addclose(&actions, descriptors.reader)
  guard status == 0 else {
    throw UnixDebugProcess.failure(status)
  }
  status = posix_spawn_file_actions_addclose(&actions, descriptors.writer)
  guard status == 0 else {
    throw UnixDebugProcess.failure(status)
  }
}

private func spawn(_ executable: String, arguments args: borrowing Span<String>,
                   environment env: borrowing Span<Debuggee.Environment>,
                   actions: inout UnixSpawnFileActions,
                   attributes: inout posix_spawnattr_t?) throws(Debuggee.Error)
    -> pid_t {
  try UnixSpawn.run(args, env: env,
                    prefix: executable) { argv, envp throws(Failure) in
    var process: pid_t = 0
    let status = executable.withCString { executable in
      posix_spawn(&process, executable, &actions, &attributes, argv, envp)
    }
    guard status == 0 else {
      throw .launch(status)
    }
    return process
  }
}
#endif
