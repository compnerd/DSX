// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
internal import Android
internal import DSXShims
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif

internal typealias UnixSpawnActionBody<Result> =
    (inout UnixSpawnFileActions) throws(Debuggee.Error) -> Result

internal enum UnixSpawnActions {
  private typealias Failure = Debuggee.Error

  internal static func run<Result>(_ body: UnixSpawnActionBody<Result>)
      throws(Debuggee.Error) -> Result {
#if os(Android)
    let result =
        try withUnsafeTemporaryAllocation(of: UnixSpawnFileActions?.self,
                                          capacity: 1) { raw throws(Failure) in
      guard let slot = raw.baseAddress else {
        throw .system(ENOMEM)
      }
      let status = dsx_spawn_file_actions_init(slot)
      guard status == 0 else {
        throw UnixError.debuggee(status, invalid: .process, support: true)
      }
      guard var actions = slot.pointee else {
        throw .system(ENOMEM)
      }
      defer {
        posix_spawn_file_actions_destroy(&actions)
      }
      return try body(&actions)
    }
    return result
#else
    var actions: UnixSpawnFileActions
#if os(anyAppleOS)
    actions = nil
#else
    actions = posix_spawn_file_actions_t()
#endif
    let status = posix_spawn_file_actions_init(&actions)
    guard status == 0 else {
      throw UnixError.debuggee(status, invalid: .process, support: true)
    }
    defer {
      posix_spawn_file_actions_destroy(&actions)
    }
    return try body(&actions)
#endif
  }

  internal static func run<Result>(_ job: borrowing Debuggee.Launch,
                                   _ body: UnixSpawnActionBody<Result>)
      throws(Debuggee.Error) -> Result {
    try run { actions throws(Debuggee.Error) in
      try configure(job, actions: &actions)
      return try body(&actions)
    }
  }

  internal static func configure(_ job: borrowing Debuggee.Launch,
                                 actions: inout UnixSpawnFileActions)
      throws(Debuggee.Error) {
    if let path = job.working {
      try path.withCString { path throws(Debuggee.Error) in
        switch posix_spawn_file_actions_addchdir(&actions, path) {
        case 0: break
        case let status:
          throw UnixError.debuggee(status, invalid: .process, support: true)
        }
      }
    }
    if let path = job.input {
      try open(path, descriptor: STDIN_FILENO, flags: O_RDONLY,
               actions: &actions)
    }
    if let path = job.output {
      try open(path, descriptor: STDOUT_FILENO,
               flags: O_WRONLY | O_CREAT | O_TRUNC, actions: &actions)
    }
    if let path = job.error {
      try open(path, descriptor: STDERR_FILENO,
               flags: O_WRONLY | O_CREAT | O_TRUNC, actions: &actions)
    }
  }

  private static func open(_ path: String, descriptor: CInt, flags: CInt,
                           actions: inout UnixSpawnFileActions)
      throws(Debuggee.Error) {
    let status = path.withCString { path in
      posix_spawn_file_actions_addopen(&actions, descriptor, path, flags,
                                       mode_t(0o666))
    }
    guard status == 0 else {
      throw UnixError.debuggee(status, invalid: .process, support: true)
    }
  }
}
#endif
