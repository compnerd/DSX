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

internal enum WaitSystem {
  internal static func wait(_ channel: CInt, timeout: Int32,
                            events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    let capacity = events.count + 1
    let deadline = if timeout < 0 {
      nil as Deadline?
    } else {
      try Deadline(milliseconds: UInt64(timeout), now: time())
    }
    return try withUnsafeTemporaryAllocation(of: pollfd.self,
                                             capacity: capacity,
                                             { polls throws(TransportError) in
      polls[0] = pollfd(fd: channel, events: Int16(POLLIN), revents: 0)
      for index in 0 ..< events.count {
        polls[index + 1] =
            pollfd(fd: events[index].descriptor, events: Int16(POLLIN),
                   revents: 0)
      }
      var remaining = timeout
      while true {
        let status = poll(polls.baseAddress, numericCast(capacity), remaining)
        if status >= 0 {
          guard status > 0 else {
            return .timeout
          }
          return polls[0].revents == 0 ? .event : .channel
        }
        guard errno == EINTR else {
          throw .read(errno)
        }
        if let deadline {
          remaining = try Int32(clamping: deadline.remaining(time()))
        }
      }
    })
  }

  private static func time() throws(TransportError) -> UInt64 {
    var value = timespec()
    guard clock_gettime(CLOCK_MONOTONIC, &value) == 0 else {
      throw .read(errno)
    }
    return UInt64(value.tv_sec) * 1_000 + UInt64(value.tv_nsec) / 1_000_000
  }
}

extension WaitHandle {
  internal func close() {
    _ = DSX::close(descriptor)
  }
}
#endif
