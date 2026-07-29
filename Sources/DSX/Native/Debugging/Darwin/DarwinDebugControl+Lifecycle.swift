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

  internal static var polling: Duration? {
    .milliseconds(1)
  }

  // MARK: - Lifecycle

  internal mutating func attach(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    let identifier = try process.native
    let release = try process.stopped
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
    var threads = try DarwinThreadList(process, control: self)
    try finish(threads)
    try restore(threads)
    // Transfer all-stop protection to owned thread suspensions. PT_DETACH
    // may resume the task, so release our task hold before entering ptrace.
    // The pending exception and thread holds protect the entire handoff.
    try threads.suspend()
    // Transfer the traced stop to BSD before selecting the final disposition.
    // PT_DETACH and a Mach reply do not acknowledge completion of that stop.
    try exceptions.restore()
    try exceptions.resume()
    let address = UnsafeMutablePointer<CChar>(bitPattern: 1)
    let detached = ptrace(PT_DETACH, identifier, address, SIGSTOP)
    let code = errno
    guard detached == 0 else {
      throw Debuggee.Error(unix: code)
    }
    defer {
      self.process = nil
      attached = false
      discard()
    }
    try exceptions.reply(nil)
    try exceptions.task.settle(process)
    try threads.resume()
    if stopped == false, kill(identifier, SIGCONT) < 0 {
      throw Debuggee.Error(unix: errno)
    }
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

#endif
