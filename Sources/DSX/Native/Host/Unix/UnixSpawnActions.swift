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

internal struct UnixSpawnActions: ~Copyable {
  internal var value: UnixSpawnFileActions

  internal init() throws(Debuggee.Error) {
#if os(Android) || os(anyAppleOS)
    var actions: posix_spawn_file_actions_t?
#else
    var actions = posix_spawn_file_actions_t()
#endif
    let status = posix_spawn_file_actions_init(&actions)
    guard status == 0 else {
      throw Debuggee.Error(process: status)
    }
#if os(Android)
    guard let actions else {
      throw .system(ENOMEM)
    }
#endif
    value = actions
  }

  deinit {
    var actions = value
    posix_spawn_file_actions_destroy(&actions)
  }
}

extension UnixSpawnActions {
  internal mutating func duplicate(_ descriptor: CInt, to destination: CInt,
                                   failure: (CInt) -> Debuggee.Error)
      throws(Debuggee.Error) {
    let status =
        posix_spawn_file_actions_adddup2(&value, descriptor, destination)
    guard status == 0 else {
      throw failure(status)
    }
  }

  internal mutating func close(_ descriptor: CInt,
                               failure: (CInt) -> Debuggee.Error)
      throws(Debuggee.Error) {
    let status = posix_spawn_file_actions_addclose(&value, descriptor)
    guard status == 0 else {
      throw failure(status)
    }
  }

  internal mutating func configure(_ launch: borrowing Debuggee.Launch)
      throws(Debuggee.Error) {
    try launch.validate()
    if let path = launch.directory {
      try path.withCString { path throws(Debuggee.Error) in
        switch posix_spawn_file_actions_addchdir(&value, path) {
        case 0: break
        case let status:
          throw Debuggee.Error(process: status)
        }
      }
    }
    if let path = launch.input {
      try open(path, descriptor: STDIN_FILENO, flags: O_RDONLY)
    }
    if let path = launch.output {
      try open(path, descriptor: STDOUT_FILENO,
               flags: O_WRONLY | O_CREAT | O_TRUNC)
    }
    if let path = launch.error {
      try open(path, descriptor: STDERR_FILENO,
               flags: O_WRONLY | O_CREAT | O_TRUNC)
    }
  }

  private mutating func open(_ path: String, descriptor: CInt, flags: CInt)
      throws(Debuggee.Error) {
    let status = path.withCString { path in
      posix_spawn_file_actions_addopen(&value, descriptor, path, flags,
                                       mode_t(0o666))
    }
    guard status == 0 else {
      throw Debuggee.Error(process: status)
    }
  }
}
#endif
