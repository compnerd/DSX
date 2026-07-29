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

internal enum UnixStream {
  internal typealias Handle = CInt

  internal static func close(_ handle: CInt) {
    _ = DSX::close(handle)
  }

  internal static func open(_ endpoint: StreamEndpoint) throws(TransportError)
      -> CInt {
    switch endpoint {
    case .descriptor(let descriptor):
      guard fcntl(descriptor, F_GETFD) >= 0 else {
        throw .descriptor(errno)
      }
      return descriptor
    case .device(let path):
      let handle = path.withCString {
        DSX::open($0, O_RDWR | O_NOCTTY | O_NONBLOCK | O_CLOEXEC)
      }
      guard handle >= 0 else {
        throw .open(errno)
      }
      do throws(TransportError) {
        try validate(handle, mode: numericCast(S_IFCHR))
        let flags = fcntl(handle, F_GETFL)
        guard flags >= 0,
            fcntl(handle, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
          throw .open(errno)
        }
      } catch {
        close(handle)
        throw error
      }
      return handle
    case .notification(let path):
      let handle = path.withCString {
        DSX::open($0, O_WRONLY | O_NONBLOCK | O_CLOEXEC)
      }
      guard handle >= 0 else {
        throw .open(errno)
      }
      do {
        try validate(handle, mode: numericCast(S_IFIFO))
      } catch {
        close(handle)
        throw error
      }
      return handle
    case .pipe(let path):
      let handle = path.withCString {
        DSX::open($0, O_RDWR | O_NONBLOCK | O_CLOEXEC)
      }
      guard handle >= 0 else {
        throw .open(errno)
      }
      do {
        try validate(handle, mode: numericCast(S_IFIFO))
      } catch {
        close(handle)
        throw error
      }
      return handle
    }
  }

  internal static func wait(_ handle: CInt, timeout: Int32,
                            events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    try WaitHandle(handle).wait(timeout: timeout, events: events)
  }

  internal static func receive(_ handle: CInt,
                               _ buffer: UnsafeMutableRawPointer,
                               _ count: Int) throws(TransportError) -> Int {
    while true {
      let result = DSX::read(handle, buffer, count)
      if result >= 0 {
        return result
      }
      if errno == EAGAIN || errno == EWOULDBLOCK {
        try ready(handle, events: Int16(POLLIN))
        continue
      }
      guard errno == EINTR else {
        throw .read(errno)
      }
    }
  }

  internal static func transmit(_ handle: CInt, _ buffer: UnsafeRawPointer,
                                _ count: Int) throws(TransportError) -> Int {
    while true {
      let result = DSX::write(handle, buffer, count, suppressing: SIGPIPE)
      if result >= 0 {
        return result
      }
      if errno == EAGAIN || errno == EWOULDBLOCK {
        try ready(handle, events: Int16(POLLOUT))
        continue
      }
      guard errno == EINTR else {
        throw .write(errno)
      }
    }
  }

  private static func validate(_ handle: CInt, mode: UInt32)
      throws(TransportError) {
    var status = stat()
    guard fstat(handle, &status) == 0 else {
      throw .type(errno)
    }
    let mask: UInt32 = numericCast(S_IFMT)
    guard UInt32(status.st_mode) & mask == mode else {
      throw .type(EINVAL)
    }
  }

  private static func ready(_ handle: CInt, events: Int16)
      throws(TransportError) {
    var descriptor = pollfd(fd: handle, events: events, revents: 0)
    while poll(&descriptor, 1, -1) < 0 {
      guard errno == EINTR else {
        throw events == Int16(POLLOUT) ? .write(errno) : .read(errno)
      }
    }
  }
}
#endif
