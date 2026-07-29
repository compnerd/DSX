// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin

internal struct DarwinEventQueue: ~Copyable {
  internal let descriptor: CInt
  internal private(set) var exited = false
  private let ports: mach_port_t

  internal init(_ port: mach_port_t, process: pid_t) throws(Debuggee.Error) {
    var ports = mach_port_t(MACH_PORT_NULL)
    let status =
        mach_port_allocate(mach_task_self_, MACH_PORT_RIGHT_PORT_SET, &ports)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
    var retained = false
    defer {
      if retained == false {
        _ = mach_port_mod_refs(mach_task_self_, ports, MACH_PORT_RIGHT_PORT_SET,
                               -1)
      }
    }
    let inserted = mach_port_move_member(mach_task_self_, port, ports)
    guard inserted == KERN_SUCCESS else {
      throw Debuggee.Error(mach: inserted, invalid: .process)
    }
    let descriptor = kqueue()
    if descriptor == -1 {
      throw Debuggee.Error(unix: errno)
    }
    defer {
      if retained == false {
        _ = DSX::close(descriptor)
      }
    }
    guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    // Mach exceptions cover stops; process exit can occur without one.
    let changes: InlineArray<2, kevent64_s> = [
      kevent64_s(ident: UInt64(ports), filter: Int16(EVFILT_MACHPORT),
                 flags: UInt16(EV_ADD), fflags: 0, data: 0, udata: 0,
                 ext: (0, 0)),
      kevent64_s(ident: UInt64(process), filter: Int16(EVFILT_PROC),
                 flags: UInt16(EV_ADD), fflags: NOTE_EXIT, data: 0, udata: 0,
                 ext: (0, 0)),
    ]
    let result = changes.span.withUnsafeBufferPointer {
      kevent64(descriptor, $0.baseAddress, CInt($0.count), nil, 0, 0, nil)
    }
    guard result == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    self.descriptor = descriptor
    self.ports = ports
    retained = true
  }

  deinit {
    _ = DSX::close(descriptor)
    _ = mach_port_mod_refs(mach_task_self_, ports, MACH_PORT_RIGHT_PORT_SET, -1)
  }

  internal mutating func drain() throws(Debuggee.Error) {
    var events = InlineArray<2, kevent64_s>(repeating: kevent64_s())
    var timeout = timespec()
    var span = events.mutableSpan
    let result = span.withUnsafeMutableBufferPointer {
      kevent64(descriptor, nil, 0, $0.baseAddress, CInt($0.count), 0, &timeout)
    }
    if result < 0 {
      guard errno == EINTR else {
        throw Debuggee.Error(unix: errno)
      }
      return
    }
    for index in 0 ..< Int(result) {
      if events[index].filter == Int16(EVFILT_PROC) {
        // NOTE_EXIT may precede waitpid's terminal status. Retain readiness
        // until the controller reaps the process and releases this queue.
        exited = true
      }
    }
  }
}
#endif
