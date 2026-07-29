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

internal struct UnixDescriptors: ~Copyable {
  internal var reader: CInt
  internal var writer: CInt

  internal init(reader: CInt, writer: CInt) {
    self.reader = reader
    self.writer = writer
  }

  internal init() throws(Debuggee.Error) {
    var descriptors: InlineArray<2, CInt> = [-1, -1]
    let status = withUnsafeMutablePointer(to: &descriptors) { descriptors in
      descriptors.withMemoryRebound(to: CInt.self, capacity: 2) { values in
#if os(anyAppleOS)
        Darwin.pipe(values)
#else
        DSX::pipe2(values, O_CLOEXEC)
#endif
      }
    }
    guard status == 0 else {
      throw Debuggee.Error(unix: errno, invalid: .process, support: true)
    }
    var result = UnixDescriptors(reader: descriptors[0], writer: descriptors[1])
    try result.isolate()
    self = consume result
  }

  /// Keeps owned descriptors out of the standard-stream range across spawn.
  internal mutating func isolate(minimum: CInt = STDERR_FILENO + 1)
      throws(Debuggee.Error) {
    func isolate(_ descriptor: inout CInt) throws(Debuggee.Error) {
      if descriptor < 0 {
        return
      }
      if descriptor < minimum {
        let replacement = fcntl(descriptor, F_DUPFD_CLOEXEC, minimum)
        if replacement == -1 {
          throw Debuggee.Error(unix: errno, invalid: .process)
        }
        _ = DSX::close(descriptor)
        descriptor = replacement
      } else {
        if fcntl(descriptor, F_SETFD, FD_CLOEXEC) == -1 {
          throw Debuggee.Error(unix: errno, invalid: .process)
        }
      }
    }
    try isolate(&reader)
    try isolate(&writer)
  }

  deinit {
    if reader >= 0 {
      _ = DSX::close(reader)
    }
    if writer >= 0 {
      _ = DSX::close(writer)
    }
  }

  internal consuming func release() -> CInt {
    let descriptor = reader
    reader = -1
    return descriptor
  }
}
#endif
