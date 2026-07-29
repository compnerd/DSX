// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

internal struct LinuxEventSource: ~Copyable {
  private let descriptor: CInt?
  private let mask: sigset_t?

  internal var polling: Bool { descriptor == nil }

  internal init() {
    descriptor = nil
    mask = nil
  }

  internal init(_ mode: DSX.Events) throws(Debuggee.Error) {
    switch mode {
    case .polling:
      descriptor = nil
      mask = nil
    case .descriptor(let descriptor):
      let flags = fcntl(descriptor, F_GETFL)
      if flags == -1 {
        throw Debuggee.Error(unix: errno)
      }
      if flags & O_NONBLOCK == 0 {
        throw .system(EINVAL)
      }
      if flags & O_ACCMODE == O_WRONLY {
        throw .system(EINVAL)
      }
      let owned = fcntl(descriptor, F_DUPFD_CLOEXEC, STDERR_FILENO + 1)
      if owned == -1 {
        throw Debuggee.Error(unix: errno)
      }
      self.descriptor = owned
      mask = nil
    case .signals:
      var disposition = sigaction()
      guard sigaction(SIGCHLD, nil, &disposition) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
#if os(Android)
      let handler = disposition.sa_handler
#else
      let handler = disposition.__sigaction_handler.sa_handler
#endif
      guard handler == nil,
          disposition.sa_flags & (SA_NOCLDSTOP | SA_NOCLDWAIT) == 0 else {
        throw .system(EINVAL)
      }
      var signals = sigset_t()
      sigemptyset(&signals)
      sigaddset(&signals, SIGCHLD)
      var previous = sigset_t()
      let status = pthread_sigmask(SIG_BLOCK, &signals, &previous)
      guard status == 0 else {
        throw .system(status)
      }
      let descriptor = signalfd(-1, &signals, SFD_CLOEXEC | SFD_NONBLOCK)
      if descriptor == -1 {
        let error = errno
        _ = pthread_sigmask(SIG_SETMASK, &previous, nil)
        throw Debuggee.Error(unix: error)
      }
      self.descriptor = descriptor
      mask = previous
    }
  }

  deinit {
    if let descriptor {
      _ = DSX::close(descriptor)
    }
    if var mask {
      _ = pthread_sigmask(SIG_SETMASK, &mask, nil)
    }
  }

  internal func configure(_ control: inout LinuxDebugControl) {
    if var mask {
      control.unblock = sigismember(&mask, SIGCHLD) == 0
    }
  }

  internal func drain() throws(Debuggee.Error) {
    guard let descriptor else {
      return
    }
    // One signalfd record; pipes and eventfd also accept this buffer size.
    var notification = signalfd_siginfo()
    while true {
      let count = withUnsafeMutableBytes(of: &notification) {
        DSX::read(descriptor, $0.baseAddress, $0.count)
      }
      switch count {
      case 1...: continue
      case 0: throw .system(EPIPE)
      default:
        switch errno {
        case EINTR: continue
        case EAGAIN, EWOULDBLOCK: return
        default: throw Debuggee.Error(unix: errno)
        }
      }
    }
  }

  internal func wait<Failure: Error>(_ control: borrowing LinuxDebugControl,
                                     _ body: EventWait<Failure>) throws(Failure)
      -> WaitResult {
    let output = control.exhausted ? nil : control.reader
    let handles: InlineArray<2, WaitHandle> =
        [WaitHandle(descriptor ?? -1), WaitHandle(output ?? -1)]
    let timeout = descriptor == nil ? Configuration.DebuggeePollInterval : -1
    return try body(timeout, handles.span)
  }
}
#endif
