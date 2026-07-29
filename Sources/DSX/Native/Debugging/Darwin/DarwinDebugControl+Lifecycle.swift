// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)

internal import Darwin
internal import DSXShims

extension DarwinDebugControl {
  // MARK: - Capabilities

  internal static var capabilities: DebugCapabilities {
    .allocation | .detachment | .executable | .images | .libraries
        | .randomization
  }

  internal static var interval: Int32? {
    1
  }

  // MARK: - Lifecycle

  internal mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.native
    let release = try suspended(identifier)
    let exceptions = try DarwinExceptions(process, ignored: ignored)
    var denied: CInt = 0
    guard ptrace(identifier, denied: &denied) == 0 else {
      if denied == 1 {
        throw .denied
      }
      throw Debuggee.Error(unix: errno)
    }
    self.process = process
    attached = true
    self.release = release
    self.exceptions = exceptions
  }

  internal mutating func ignore(_ exceptions: Debuggee.ExceptionMask)
      throws(Debuggee.Error) {
    guard process == nil else {
      throw .state
    }
    ignored = exceptions
  }

  internal mutating func detach(_ process: ProcessIdentifier, stopped: Bool)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    guard let exceptions else {
      throw .state
    }
    try exceptions.stop()
    let threads = try DarwinThreadList(process)
    try finish(threads)
    try restore(threads)
    // Keep the signal exception pending so PT_DETACH owns the BSD stop and
    // consumes our Mach suspension before allowing its thread to proceed.
    try exceptions.restore()
    let address = UnsafeMutablePointer<CChar>(bitPattern: 1)
    let detached = ptrace(PT_DETACH, identifier, address, stopped ? SIGSTOP : 0)
    let code = errno
    guard detached == 0 else {
      throw Debuggee.Error(unix: code)
    }
    exceptions.detached()
    try exceptions.reply(nil)
    self.exceptions = nil
    self.process = nil
    attached = false
    discard()
  }

  @inline(__always)
  internal mutating func terminate(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.owned(by: self.process)
    if ptrace(PT_KILL, identifier, nil, 0) < 0 {
      if kill(identifier, SIGKILL) < 0 {
        guard errno == ESRCH else {
          throw Debuggee.Error(unix: errno)
        }
      }
    }
    // Termination is irreversible. Release pending replies and our suspension
    // without treating the dying task's invalidated ports as a failure.
    exceptions = nil
  }

  // MARK: - Cleanup

  internal mutating func discard() {
    if let reader {
      _ = DSX::close(reader)
    }
    reader = nil
    output = nil
    steps.removeAll(keepingCapacity: true)
    held.removeAll(keepingCapacity: true)
    exceptions = nil
    deferred = nil
    events.removeAll(keepingCapacity: true)
    replacement = false
    requested = false
    obsolete = false
    release = false
  }
}

private func suspended(_ process: pid_t) throws(Debuggee.Error) -> Bool {
  var info = proc_bsdinfo()
  let count = proc_pidinfo(process, PROC_PIDTBSDINFO, 0, &info,
                           Int32(MemoryLayout<proc_bsdinfo>.size))
  guard count == MemoryLayout<proc_bsdinfo>.size else {
    return false
  }
  // Do not acquire a task port or replace another debugger's exception ports.
  // task_for_pid can block for a task already stopped by its tracer.
  guard info.pbi_flags & UInt32(PROC_FLAG_TRACED) == 0 else {
    throw .denied
  }
  return info.pbi_status == SSTOP
}

#endif
