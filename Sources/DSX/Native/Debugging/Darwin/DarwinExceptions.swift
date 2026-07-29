// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims

internal final class DarwinExceptions: @unchecked Sendable {
  private let context: OpaquePointer
  private let process: pid_t
  private var task: task_t
  private var records: Array<dsx_exception_record>

  internal var pending: Bool {
    !records.isEmpty
  }

  internal var count: Int {
    records.count
  }

  internal init(_ process: ProcessIdentifier,
                ignored: Debuggee.ExceptionMask = []) throws(Debuggee.Error) {
    let task =
        try DarwinTask.attach(process,
                              retries: Configuration.Darwin.Task.Retries,
                              delay: Configuration.Darwin.Task.Delay)
    var status: kern_return_t = KERN_SUCCESS
    guard let context =
        dsx_exception_create(task.handle, ignored.rawValue, &status) else {
      throw DarwinError.debuggee(status, invalid: .process)
    }
    self.context = context
    self.process = try process.native
    self.task = task.handle
    records = []
  }

  deinit {
    _ = dsx_exception_destroy(context)
  }

  internal func receive() throws(Debuggee.Error) -> dsx_exception_record? {
    var record = dsx_exception_record()
    var received: boolean_t = 0
    let status = dsx_exception_receive(context, &record, &received)
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .process)
    }
    guard received > 0 else {
      return nil
    }
    records.append(record)
    return record
  }

  internal subscript(_ index: Int) -> dsx_exception_record {
    records[index]
  }

  internal func next() throws(Debuggee.Error) -> dsx_exception_record? {
    if pending {
      records[0]
    } else {
      try receive()
    }
  }

  internal func reply(_ signal: CInt = 0) throws(Debuggee.Error) {
    guard pending else {
      return
    }
    for record in records where record.type == EXC_SOFTWARE &&
        record.count > 1 && record.codes.0 == EXC_SOFT_SIGNAL {
      let thread = UInt(record.thread)
      let address = UnsafeMutablePointer<CChar>(bitPattern: thread)
      guard ptrace(kPTThreadUpdate, process, address, signal) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
    }
    let status = dsx_exception_reply(context)
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .process)
    }
    records.removeAll(keepingCapacity: true)
  }

  internal func accept(_ record: borrowing dsx_exception_record,
                       process: ProcessIdentifier) throws(Debuggee.Error)
      -> Bool {
    if record.task == task {
      return true
    }
    let current =
        try DarwinTask.attach(process,
                              retries: Configuration.Darwin.Task.Retries,
                              delay: Configuration.Darwin.Task.Delay)
    guard record.task == current.handle else {
      return false
    }
    try update(current)
    return true
  }

  internal func reject() throws(Debuggee.Error) {
    guard pending else {
      return
    }
    let status = dsx_exception_reject(context)
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .process)
    }
    records.removeLast()
  }

  internal func resume() throws(Debuggee.Error) {
    let status = dsx_exception_resume(context)
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .process)
    }
  }

  internal func update(_ process: ProcessIdentifier) throws(Debuggee.Error) {
    let task =
        try DarwinTask.attach(process,
                              retries: Configuration.Darwin.Task.Retries,
                              delay: Configuration.Darwin.Task.Delay)
    try update(task)
  }

  private func update(_ task: borrowing DarwinTask) throws(Debuggee.Error) {
    let status = dsx_exception_update(context, task.handle)
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .process)
    }
    self.task = task.handle
  }
}
#endif
