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

extension WaitHandle {
  internal func wait(timeout: Duration?, events: borrowing Span<WaitHandle>)
      throws(TransportError) -> WaitResult {
    let capacity = events.count + 1
    let deadline = if let timeout {
      try Deadline(timeout, now: time())
    } else {
      nil as Deadline?
    }
    return try withUnsafeTemporaryAllocation(of: pollfd.self,
                                             capacity: capacity,
                                             { polls throws(TransportError) in
      polls[0] = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
      for index in 0 ..< events.count {
        polls[index + 1] =
            pollfd(fd: events[index].descriptor, events: Int16(POLLIN),
                   revents: 0)
      }
      var remaining = timeout
      while true {
        let milliseconds = remaining.map {
          CInt(clamping: $0.rounded(to: .milliseconds(1), rule: .up))
        } ?? -1
        let status =
            poll(polls.baseAddress, numericCast(capacity), milliseconds)
        if status >= 0 {
          if status == 0 {
            if let deadline {
              let rest = try deadline.remaining(at: time())
              if rest > .zero {
                remaining = rest
                continue
              }
            }
            return .timeout
          }
          return polls[0].revents == 0 ? .event : .channel
        }
        guard errno == EINTR else {
          throw .read(errno)
        }
        if let deadline {
          remaining = try deadline.remaining(at: time())
        }
      }
    })
  }

  internal func close() {
    _ = DSX::close(descriptor)
  }
}

private func time() throws(TransportError) -> Duration {
  var value = Duration.zero
  let status = clock(&value)
  guard status == 0 else {
    throw .read(status)
  }
  return value
}
#endif
