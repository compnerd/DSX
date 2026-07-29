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
extension UnixDescriptors {
  internal init(terminal: Debuggee.TerminalSize?) throws(Debuggee.Error) {
    var descriptors = UnixDescriptors(reader: -1, writer: -1)
    descriptors.reader = pseudoterminal(O_RDWR | O_NOCTTY)
    guard descriptors.reader >= 0 else {
      throw Debuggee.Error(unix: errno)
    }
    try descriptors.isolate()
    guard grantpt(descriptors.reader) == 0,
        unlockpt(descriptors.reader) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    var path = Array<CChar>(repeating: 0, count: Int(PATH_MAX))
    let status = path.withUnsafeMutableBufferPointer { path in
      guard let base = path.baseAddress else {
        return EINVAL
      }
      return ptsname_r(descriptors.reader, base, path.count)
    }
    guard status == 0 else {
      throw Debuggee.Error(unix: status)
    }
    descriptors.writer = path.withUnsafeBufferPointer { path in
      guard let base = path.baseAddress else {
        return CInt(-1)
      }
      return DSX::open(base, O_RDWR | O_NOCTTY | O_CLOEXEC)
    }
    guard descriptors.writer >= 0 else {
      throw Debuggee.Error(unix: errno)
    }
    try descriptors.isolate()
    if let terminal {
      guard dsx_terminal_size(descriptors.writer, terminal.columns,
                              terminal.rows) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
    }
    let flags = fcntl(descriptors.reader, F_GETFL)
    guard flags >= 0,
        fcntl(descriptors.reader, F_SETFL, flags | O_NONBLOCK) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    self = consume descriptors
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
