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
          guard ptrace(PTRACE_ATTACH, thread, nil, nil) == 0 else {
            if errno == ESRCH {
              continue
            }
            throw UnixDebugProcess.failure(errno)
          }
          traced.insert(thread)
          try collect(thread)
          stopped.insert(thread)
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
        _ = stopped.remove(thread)
      }
      throw error
    }
    self.process = process
    attached = true
    configured = true
    for thread in traced {
      owners[thread] = process
    }
    let thread = ThreadIdentifier(rawValue: UInt64(leader))
    let identifier = ProcessThreadIdentifier(process: process, thread: thread)
    let stop = Debuggee.Stop(thread: identifier, reason: .signal(SIGSTOP))
    events.append(.stopped(stop))
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let identifier = try process.native
    if self.process == process {
      switch stopped {
      case true:
        break
      case false:
        _ = kill(identifier, SIGCONT)
      }
      if children.isEmpty {
        let failure = release(stopped: stopped)
        reset()
        if let failure {
          throw failure
        }
      } else {
        let failure = release(process, stopped: stopped)
        promote()
        if let failure {
          throw failure
        }
      }
    } else {
      guard children.contains(identifier) else {
        throw .process
      }
      if let failure = release(process, stopped: stopped) {
        throw failure
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
    if let failure = release(fork.child.process, stopped: false) {
      throw failure
    }
  }

  internal mutating func close() throws(Debuggee.Error) {
    guard case .some = process else {
      return
    }
    let failure = release(stopped: false)
    reset()
    if let failure {
      throw failure
    }
  }

  // MARK: - Cleanup

  private static func detach(_ process: pid_t,
                             stopped: Bool) throws(Debuggee.Error) {
    let signal = UnsafeMutableRawPointer(bitPattern: stopped ? Int(SIGSTOP) : 0)
    guard ptrace(PTRACE_DETACH, process, nil, signal) == 0 else {
      guard errno == ESRCH else {
        throw UnixDebugProcess.failure(errno)
      }
      return
    }
  }

  internal mutating func release() throws(Debuggee.Error) {
    if let failure = release(stopped: false) {
      throw failure
    }
  }

  private mutating func release(stopped: Bool) -> Debuggee.Error? {
    var failure: Debuggee.Error?
    for thread in owners.keys {
      do throws(Debuggee.Error) {
        try LinuxDebugControl.detach(thread, stopped: stopped)
      } catch {
        if case .none = failure {
          failure = error
        }
      }
    }
    children.removeAll(keepingCapacity: true)
    self.stopped.removeAll(keepingCapacity: true)
    stepping.removeAll(keepingCapacity: true)
    owners.removeAll(keepingCapacity: true)
    return failure
  }

  private mutating func release(_ process: ProcessIdentifier, stopped: Bool)
      -> Debuggee.Error? {
    var failure: Debuggee.Error?
    for record in owners where record.value == process {
      let thread = record.key
      do throws(Debuggee.Error) {
        try LinuxDebugControl.detach(thread, stopped: stopped)
      } catch {
        if case .none = failure {
          failure = error
        }
      }
    }
    if let thread, owners[thread] == process {
      status = nil
      self.thread = nil
    }
    events.removeAll { event in
      event.process == process
    }
    for record in owners where record.value == process {
      _ = entries.remove(record.key)
      _ = newborn.remove(record.key)
      _ = self.stopped.remove(record.key)
      _ = stepping.remove(record.key)
    }
    while let thread = owners.first(where: { $0.value == process })?.key {
      owners.removeValue(forKey: thread)
    }
    _ = children.remove(pid_t(process.rawValue))
    return failure
  }

  internal mutating func depart(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    if self.process == process {
      if children.isEmpty {
        try release()
        reset()
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
      throw UnixDebugProcess.failure(errno)
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
