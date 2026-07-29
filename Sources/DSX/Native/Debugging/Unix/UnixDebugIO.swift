// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
#if os(anyAppleOS)
internal import Darwin
#elseif os(Android)
@preconcurrency internal import Android
#elseif os(Linux) || os(FreeBSD) || os(OpenBSD)
internal import Glibc
#endif
internal import DSXShims

#if os(anyAppleOS) || os(Android) || os(Linux)
internal enum UnixPseudoTerminal {
  internal static func open(_ descriptors: inout UnixDescriptors,
                            terminal: Debuggee.TerminalSize? = nil)
      throws(Debuggee.Error) {
    descriptors[0] = pseudoterminal(O_RDWR | O_NOCTTY)
    guard descriptors[0] >= 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    var complete = false
    defer {
      switch complete {
      case true:
        break
      case false:
        for index in 0 ..< 2 where descriptors[index] >= 0 {
          _ = DSX::close(descriptors[index])
          descriptors[index] = -1
        }
      }
    }
    try UnixSpawn.isolate(&descriptors[0])
    guard grantpt(descriptors[0]) == 0, unlockpt(descriptors[0]) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    var path = Array<CChar>(repeating: 0, count: Int(PATH_MAX))
    let status = path.withUnsafeMutableBufferPointer { path in
      guard let base = path.baseAddress else {
        return EINVAL
      }
      return ptsname_r(descriptors[0], base, path.count)
    }
    guard status == 0 else {
      throw UnixDebugProcess.failure(status)
    }
    descriptors[1] = path.withUnsafeBufferPointer { path in
      guard let base = path.baseAddress else {
        return CInt(-1)
      }
      return DSX::open(base, O_RDWR | O_NOCTTY | O_CLOEXEC)
    }
    guard descriptors[1] >= 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    try UnixSpawn.isolate(&descriptors[1])
    if let terminal {
      guard dsx_terminal_size(descriptors[1], terminal.columns,
                              terminal.rows) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
    }
    let flags = fcntl(descriptors[0], F_GETFL)
    guard flags >= 0,
        fcntl(descriptors[0], F_SETFL, flags | O_NONBLOCK) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
    complete = true
  }
}

@_transparent
private func pseudoterminal(_ flags: CInt) -> CInt {
#if os(anyAppleOS)
  posix_openpt(flags)
#else
  "/dev/ptmx".withCString { path in
    DSX::open(path, flags | O_CLOEXEC)
  }
#endif
}
#endif

#endif
