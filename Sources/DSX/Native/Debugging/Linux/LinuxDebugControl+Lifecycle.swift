// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

extension LinuxDebugControl {
  // MARK: - Capabilities

  internal static var capabilities: DebugCapabilities {
    .allocation | .auxiliary | .detachment | .executable | .fork
        | .passthrough | .randomization | .signal | .svr4 | .syscalls
        | .threads | .vfork
  }

  internal static var interval: Int32? {
    nil
  }

  internal mutating func ignore(_: Debuggee.ExceptionMask)
      throws(Debuggee.Error) {
    throw .unsupported
  }

  // MARK: - Lifecycle

  internal mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let leader = try process.native
    var traced = Set<pid_t>()
    do throws(Debuggee.Error) {
      var pending = true
      while pending {
        pending = false
        for identifier in try process.threads {
          let thread = try identifier.thread.native
          if traced.contains(thread) {
            continue
          }
          pending = true
          // SEIZE avoids the legacy exec trap and SIGSTOP races of ATTACH.
          guard ptrace(PTRACE_SEIZE, thread, nil, nil) == 0 else {
            if errno == ESRCH {
              continue
            }
            throw Debuggee.Error(unix: errno)
          }
          traced.insert(thread)
          threads[thread] = LinuxThreadState(process: process)
          try interrupt(thread)
        }
      }
      guard traced.contains(leader) else {
        throw .process
      }
      for thread in traced {
        try LinuxDebugControl.configure(thread)
      }
    } catch {
      for thread in traced {
        _ = ptrace(PTRACE_DETACH, thread, nil, nil)
        threads.removeValue(forKey: thread)
      }
      throw error
    }
    self.process = process
    attached = true
    configured = true
    let thread = ThreadIdentifier(rawValue: UInt64(leader))
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    let stop = Debuggee.Stop(thread: identifier, reason: .signal(SIGSTOP))
    events.append(.stopped(stop))
  }

  private mutating func interrupt(_ thread: pid_t) throws(Debuggee.Error) {
    guard ptrace(PTRACE_INTERRUPT, thread, nil, nil) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    while true {
      let status = try collect(thread)
      threads[thread]?.stopped = true
      if status >> 16 == PTRACE_EVENT_STOP {
        return
      }
      // Preserve a signal-delivery stop that preceded the interrupt request.
      threads[thread]?.signal = try siginfo_t(thread)
      guard ptrace(PTRACE_CONT, thread, nil, nil) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      threads[thread]?.stopped = false
    }
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let identifier = try process.native
    guard self.process == process || children.contains(identifier) else {
      throw .process
    }
    try release(process, stopped: stopped)
    if self.process == process {
      if children.isEmpty {
        reset()
      } else {
        promote()
      }
    }
  }

  internal mutating func discard(_ fork: borrowing Debuggee.Fork)
      throws(Debuggee.Error) {
    let parent = try fork.parent.process.native
    guard process == fork.parent.process || children.contains(parent) else {
      throw .process
    }
    let child = try fork.child.process.native
    guard children.contains(child) else {
      throw .process
    }
    try release(fork.child.process, stopped: false)
  }

  internal mutating func close() throws(Debuggee.Error) {
    guard let process else {
      return
    }
    var failure: Debuggee.Error?
    var pending = [process]
    var visited = Array<ProcessIdentifier>()
    while let process = pending.popLast() {
      if visited.contains(process) {
        continue
      }
      visited.append(process)
      do throws(Debuggee.Error) {
        try release(process, stopped: false)
      } catch {
        if failure == nil {
          failure = error
        }
      }
      for child in children {
        let process = ProcessIdentifier(rawValue: UInt64(child))
        if visited.contains(process) == false {
          pending.append(process)
        }
      }
    }
    if threads.isEmpty {
      reset()
    } else {
      if threads.values.contains(where: { $0.process == process }) == false {
        promote()
      }
    }
    if let failure {
      throw failure
    }
  }

  // MARK: - Cleanup

  private mutating func release(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    // Detach requires a ptrace-stop. A running tracee also produces ESRCH.
    // Revisit the collection because a clone stop can introduce more threads.
    while true {
      let pending = threads.compactMap { record in
        record.value.process == process && (record.value.stopped == false ||
            record.value.pending != nil)
            ? record.key : nil
      }
      guard !pending.isEmpty else {
        break
      }
      for thread in pending {
        try suspend(thread, process: process)
      }
    }
    var failure: Debuggee.Error?
    var detached = false
    for record in threads where record.value.process == process {
      let thread = record.key
      if ptrace(PTRACE_DETACH, thread, nil, nil) == 0 {
        detached = true
        threads.removeValue(forKey: thread)
        continue
      }
      let code = errno
      if code == ESRCH, tgkill(pid_t(process.rawValue), thread, 0) < 0 {
        if errno == ESRCH {
          threads.removeValue(forKey: thread)
          continue
        }
      }
      if failure == nil {
        failure = Debuggee.Error(unix: code)
      }
    }
    // SIGCONT also cancels a SIGSTOP queued while another ptrace-stop won
    // the race. Send it after detaching, never before collecting the stops.
    if detached,
        kill(pid_t(process.rawValue), stopped ? SIGSTOP : SIGCONT) < 0 {
      switch errno {
      case ESRCH:
        break
      default:
        if failure == nil {
          failure = Debuggee.Error(unix: errno)
        }
      }
    }
    if let thread, threads[thread] == nil {
      status = nil
      self.thread = nil
    }
    if threads.values.contains(where: { $0.process == process }) == false {
      events.removeAll { event in
        event.process == process
      }
      _ = children.remove(pid_t(process.rawValue))
    }
    if let failure {
      throw failure
    }
  }

  private mutating func suspend(_ native: pid_t, process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let owner = try process.native
    if threads[native]?.pending == nil {
      if tgkill(owner, native, SIGSTOP) < 0 {
        guard errno == ESRCH else {
          throw Debuggee.Error(unix: errno)
        }
      }
    }
    while true {
      var status: CInt = 0
      switch (threads[native]?.pending, thread == native ? self.status : nil) {
      case (.some(let pending), _):
        status = pending
      case (nil, .some(let pending)):
        status = pending
        self.status = nil
        thread = nil
      case (nil, nil):
        var result: pid_t
        repeat {
          result = waitpid(native, &status, __WALL)
        } while result < 0 && errno == EINTR
        if result < 0 {
          let code = errno
          if code == ECHILD || code == ESRCH, tgkill(owner, native, 0) < 0 {
            if errno == ESRCH {
              threads.removeValue(forKey: native)
              return
            }
          }
          throw Debuggee.Error(unix: code)
        }
        guard result == native else {
          throw .state
        }
      }
      threads[native]?.pending = status
      if case .some = UnixWaitStatus(status).exit {
        threads.removeValue(forKey: native)
        return
      }
      guard UnixWaitStatus(status).stopped else {
        throw .state
      }
      let code = status >> 16
      if code > 0 {
        guard let event = try translate(code, thread: native,
                                        process: process) else {
          threads[native]?.pending = nil
          continue
        }
        events.append(event)
      }
      threads[native]?.pending = nil
      threads[native]?.stopped = true
      return
    }
  }

  internal mutating func depart(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    if self.process == process {
      if children.isEmpty {
        try close()
      } else {
        promote()
      }
    } else {
      _ = children.remove(pid_t(process.rawValue))
    }
  }

  private mutating func promote() {
    guard let child = children.first else {
      return
    }
    _ = children.remove(child)
    process = ProcessIdentifier(rawValue: UInt64(child))
  }

  internal static func configure(_ process: pid_t) throws(Debuggee.Error) {
    let options = UnsafeMutableRawPointer(bitPattern: LinuxDebugControl.options)
    guard ptrace(PTRACE_SETOPTIONS, process, nil, options) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
  }

  private static var options: UInt {
    PTRACE_O_TRACESYSGOOD | PTRACE_O_TRACEFORK | PTRACE_O_TRACEVFORK
        | PTRACE_O_TRACECLONE | PTRACE_O_TRACEEXEC | PTRACE_O_TRACEVFORKDONE
        | PTRACE_O_TRACEEXIT
  }

  internal mutating func reset() {
    if let reader {
      _ = DSX::close(reader)
    }
    self = LinuxDebugControl()
  }
}
#endif
