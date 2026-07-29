// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux) || os(FreeBSD) || os(OpenBSD)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

internal enum WritePolicy {
  internal static func write(_ handle: CInt, _ bytes: UnsafeRawPointer?,
                             _ count: Int, suppressing signal: CInt) -> Int {
    var blocked = sigset_t()
    sigemptyset(&blocked)
    sigaddset(&blocked, signal)
    var previous = sigset_t()
    let status = pthread_sigmask(SIG_BLOCK, &blocked, &previous)
    guard status == 0 else {
      errno = status
      return -1
    }
    var pending = sigset_t()
    guard sigpending(&pending) == 0 else {
      let error = errno
      _ = pthread_sigmask(SIG_SETMASK, &previous, nil)
      errno = error
      return -1
    }
    let inherited = sigismember(&previous, signal) == 1 ||
        sigismember(&pending, signal) == 1
    let ignored = dsx_signal_ignored(signal)
    guard ignored >= 0 else {
      let error = errno
      _ = pthread_sigmask(SIG_SETMASK, &previous, nil)
      errno = error
      return -1
    }
    let result = DSX::write(handle, bytes, count)
    let error = errno
    if result < 0, error == EPIPE, inherited == false, ignored == 0 {
      var received: CInt = 0
      _ = sigwait(&blocked, &received)
    }
    _ = pthread_sigmask(SIG_SETMASK, &previous, nil)
    errno = error
    return result
  }
}
#endif
