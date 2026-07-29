// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import Darwin
internal import DSXShims

internal final class DarwinExceptions: @unchecked Sendable {
  private static let delay = Duration.milliseconds(10)
  private static let timeout = Duration.seconds(2)
  private static let retries = 9

  private let context: OpaquePointer
  private let process: pid_t
  private var queue: DarwinEventQueue
  internal private(set) var task: DarwinTask
  private var records: Array<dsx_exception_record>
  private var signals = Array<Signal>()

  private struct Signal: Equatable {
    internal let thread: ThreadIdentifier
    internal let number: CInt
  }

  internal var pending: Bool {
    records.isEmpty == false
  }

  internal var descriptor: CInt { queue.descriptor }
  internal var exited: Bool { queue.exited }

  internal var count: Int {
    records.count
  }

  internal init(_ process: ProcessIdentifier,
                ignored: Debuggee.ExceptionMask = []) throws(Debuggee.Error) {
    let task =
        try DarwinTask(process, retries: DarwinExceptions.retries,
                       delay: DarwinExceptions.delay)
    var status: kern_return_t = KERN_SUCCESS
    guard let context =
        dsx_exception_create(task.handle, ignored.rawValue, &status) else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
    do throws(Debuggee.Error) {
      queue = try DarwinEventQueue(dsx_exception_port(context),
                                   process: process.native)
    } catch {
      _ = dsx_exception_destroy(context)
      throw error
    }
    self.context = context
    self.process = try process.native
    self.task = task
    records = []
  }

  deinit {
    _ = dsx_exception_destroy(context)
  }

  internal func receive() throws(Debuggee.Error) -> dsx_exception_record? {
    try queue.drain()
    while true {
      var record = dsx_exception_record()
      var received: boolean_t = 0
      let status = dsx_exception_receive(context, &record, &received)
      guard status == KERN_SUCCESS else {
        throw Debuggee.Error(mach: status, invalid: .process)
      }
      guard received > 0 else {
        return nil
      }
      if record.task == task.handle, signals.isEmpty == false,
          let number = record.signal {
        let signal =
            try Signal(thread: ThreadIdentifier(mach: record.thread),
                       number: number)
        if let index = signals.firstIndex(of: signal) {
          try update(record.thread, signal: number)
          if records.isEmpty {
            try resume()
          }
          let status = dsx_exception_reply(context, KERN_SUCCESS)
          guard status == KERN_SUCCESS else {
            throw Debuggee.Error(mach: status, invalid: .process)
          }
          signals.remove(at: index)
          continue
        }
      }
      records.append(record)
      return record
    }
  }

  internal subscript(_ index: Int) -> dsx_exception_record {
    records[index]
  }

  internal func next() throws(Debuggee.Error) -> dsx_exception_record? {
    try pending ? records[0] : receive()
  }

  // Nil leaves the kernel signal disposition unchanged; zero suppresses it.
  internal func reply(_ signal: CInt? = 0) throws(Debuggee.Error) {
    guard pending else {
      return
    }
    if let signal {
      for record in records {
        guard let original = record.signal else {
          continue
        }
        if signal == 0 || signal == original || signal == SIGKILL {
          try update(record.thread, signal: signal)
        } else {
          // XNU retains the original signal's properties across PT_THUPDATE.
          // Post the replacement to this thread, suppress the original, and
          // forward the replacement's own exception without another stop.
          let delivery =
              try Signal(thread: ThreadIdentifier(mach: record.thread),
                         number: signal)
          guard __pthread_kill(record.thread, signal) == 0 else {
            throw Debuggee.Error(unix: errno)
          }
          if signals.contains(delivery) == false {
            signals.append(delivery)
          }
          try update(record.thread, signal: 0)
        }
      }
    }
    let status = dsx_exception_drain(context)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
    records.removeAll(keepingCapacity: true)
  }

  internal func stop() throws(Debuggee.Error) {
    for record in records where record.task == task.handle &&
        record.type == EXC_SOFTWARE && record.count > 1 &&
        record.codes.0 == EXC_SOFT_SIGNAL && record.codes.1 == SIGSTOP {
      return
    }
    guard kill(process, SIGSTOP) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    try reply()
    try resume()
    let deadline = try Deadline(DarwinExceptions.timeout, now: Host.time)
    while true {
      if let record = try receive() {
        if record.task == task.handle {
          if record.type == EXC_SOFTWARE, record.count > 1,
              record.codes.0 == EXC_SOFT_SIGNAL, record.codes.1 == SIGSTOP {
            return
          }
          try reply()
        } else {
          try reject()
        }
        try resume()
      }
      guard try deadline.remaining(at: Host.time) > .zero else {
        throw .system(ETIMEDOUT)
      }
      let delay = Tuning.Debuggee.backoff.rounded(to: .microseconds(1),
                                                  rule: .up)
      _ = usleep(useconds_t(delay))
    }
  }

  internal func accept(_ record: borrowing dsx_exception_record,
                       process: ProcessIdentifier) throws(Debuggee.Error)
      -> Bool {
    if record.task == task.handle {
      return true
    }
    let current =
        try DarwinTask(process, retries: DarwinExceptions.retries,
                       delay: DarwinExceptions.delay)
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
    let status = dsx_exception_reply(context, KERN_FAILURE)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
    records.removeLast()
  }

  internal func resume() throws(Debuggee.Error) {
    let status = dsx_exception_resume(context)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
  }

  internal func restore() throws(Debuggee.Error) {
    let status = dsx_exception_restore(context)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
  }

  internal func update(_ process: ProcessIdentifier) throws(Debuggee.Error) {
    let task =
        try DarwinTask(process, retries: DarwinExceptions.retries,
                       delay: DarwinExceptions.delay)
    try update(task)
  }

  private func update(_ task: borrowing DarwinTask) throws(Debuggee.Error) {
    let status = dsx_exception_update(context, task.handle)
    guard status == KERN_SUCCESS else {
      throw Debuggee.Error(mach: status, invalid: .process)
    }
    self.task = copy task
    signals.removeAll(keepingCapacity: true)
  }

  private func update(_ thread: thread_act_t, signal: CInt)
      throws(Debuggee.Error) {
    let address = UnsafeMutablePointer<CChar>(bitPattern: UInt(thread))
    guard ptrace(PT_THUPDATE, process, address, signal) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
  }
}

extension dsx_exception_record {
  fileprivate var signal: CInt? {
    if type == EXC_SOFTWARE, count > 1, codes.0 == EXC_SOFT_SIGNAL {
      CInt(exactly: codes.1)
    } else {
      nil
    }
  }
}
#endif
