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
  internal static var daemonization: DaemonizationOrder {
    .after
  }

  internal static var interrupt: UInt8 {
    UInt8(SIGSTOP)
  }

  internal static var kernel: String? {
    var information = utsname()
    guard uname(&information) == 0 else {
      return nil
    }
    return withUnsafeBytes(of: &information.version) { bytes in
      let count = bytes.firstIndex(of: 0) ?? bytes.count
      return String(decoding: bytes.prefix(count), as: UTF8.self)
    }
  }

  internal static var release: String? {
    var information = utsname()
    guard uname(&information) == 0 else {
      return nil
    }
    return withUnsafeBytes(of: &information.release) { bytes in
      let count = bytes.firstIndex(of: 0) ?? bytes.count
      return String(decoding: bytes.prefix(count), as: UTF8.self)
    }
  }

  internal static func initialize() -> String? {
    nil
  }

  internal static func isolate() throws(SessionIsolationError) {
    guard setsid() >= 0 || errno == EPERM else {
      throw .system(errno)
    }
  }

  internal static func daemonize() throws(DaemonizationError) -> Bool {
    let first = DSX::fork()
    guard first >= 0 else {
      throw .system(errno)
    }
    if first > 0 {
      return false
    }

    guard setsid() >= 0 else {
      throw .system(errno)
    }

    let second = DSX::fork()
    guard second >= 0 else {
      throw .system(errno)
    }
    if second > 0 {
      DSX::_exit(0)
    }

    _ = DSX::close(STDIN_FILENO)
    _ = DSX::close(STDOUT_FILENO)
    _ = DSX::close(STDERR_FILENO)
    let input = "/dev/null".withCString { path in
      DSX::open(path, O_RDONLY)
    }
    guard input == STDIN_FILENO else {
      throw .system(errno)
    }
    let output = "/dev/null".withCString { path in
      DSX::open(path, O_WRONLY)
    }
    guard output == STDOUT_FILENO else {
      throw .system(errno)
    }
    let error = "/dev/null".withCString { path in
      DSX::open(path, O_WRONLY)
    }
    guard error == STDERR_FILENO else {
      throw .system(errno)
    }
    return true
  }
}

extension Debuggee.Process.Info {
  internal func matches(_ candidate: String) -> Bool {
    if name == candidate {
      return true
    }
    guard let separator = name.lastIndex(of: "/") else {
      return false
    }
    return name[name.index(after: separator)...] == candidate
  }
}
#endif
