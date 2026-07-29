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
      throw UnixError.debuggee(errno, invalid: .process, support: true)
    }
    do {
      try UnixSpawn.isolate(&descriptors[0])
      try UnixSpawn.isolate(&descriptors[1])
      self.init(reader: descriptors[0], writer: descriptors[1])
    } catch {
      _ = DSX::close(descriptors[0])
      _ = DSX::close(descriptors[1])
      throw error
    }
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
