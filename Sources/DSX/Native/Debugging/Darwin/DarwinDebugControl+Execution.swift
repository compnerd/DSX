// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)

internal import Darwin
internal import DSXShims

extension DarwinDebugControl {
  // MARK: - Execution

  internal mutating func prepare(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let process, !breakpoints.isEmpty else {
      return
    }
    let threads = try DarwinThreadList(process)
    try configure(threads)
  }

  internal mutating func resume(_ actions: borrowing Debuggee.Continuations)
      throws(Debuggee.Error) {
    guard let process else {
      throw .state
    }
    if requested, obsolete {
      let identifier = try process.native
      guard kill(identifier, SIGCONT) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      requested = false
      obsolete = false
    }
    let threads = try DarwinThreadList(process)
    try configure(threads)
    let plan =
        try DarwinContinuationPlan(actions, process: process, threads: threads)
    if plan.interrupt {
      return try interrupt(process)
    }
    try hold(actions, process: process, threads: threads)
    let replacement = self.replacement
    self.replacement = false
    let signal = replacement ? 0 : plan.signal
    if let exceptions, exceptions.pending {
      if replacement, plan.signal != 0 {
        let identifier = try process.native
        guard kill(identifier, plan.signal) == 0 else {
          throw Debuggee.Error(unix: errno)
        }
      }
      try exceptions.reply(signal)
      do throws(Debuggee.Error) {
        try step(actions, process: process, threads: threads)
      } catch {
        try? exceptions.resume()
        throw error
      }
      return try exceptions.resume()
    }
    try step(actions, process: process, threads: threads)
    let identifier = try process.native
    let address = UnsafeMutablePointer<CChar>(bitPattern: 1)
    guard ptrace(plan.request, identifier, address, signal) == 0 else {
      throw Debuggee.Error(unix: errno)
    }
    _ = awaken(identifier)
    if release {
      release = false
      _ = kill(identifier, SIGCONT)
    }
    if replacement, plan.signal != 0 {
      guard kill(identifier, plan.signal) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
    }
  }

  internal mutating func recover() throws(Debuggee.Error) {
    guard let process else {
      return
    }
    try restore(process)
    let identifier = try process.native
    if kill(identifier, SIGSTOP) < 0 {
      guard errno == ESRCH else {
        throw Debuggee.Error(unix: errno)
      }
    }
  }

  // MARK: - Input and Output

  internal mutating func output(_ process: ProcessIdentifier,
                                into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    _ = try forward(process, current: self.process, pending: &self.output,
                    into: &output)
  }

  internal func input(_ process: ProcessIdentifier,
                      bytes: borrowing Span<UInt8>) throws(Debuggee.Error) {
    guard self.process == process, let reader else {
      throw .state
    }
    try write(reader, bytes: bytes)
  }

  // MARK: - Threads

  private mutating func hold(_ actions: borrowing Debuggee.Continuations,
                             process: ProcessIdentifier,
                             threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    try restore(threads)
    do throws(Debuggee.Error) {
      var selected: ThreadIdentifier?
      var count = 0
      for index in 0 ..< threads.count {
        let thread = threads[index]
        let identifier = try identity(thread)
        let candidate =
            ProcessThreadIdentifier(process: process, thread: identifier)
        let action = actions.action(candidate)
        switch action?.operation {
        case nil, .stop:
          continue
        case .resume, .step:
          count += 1
          selected = count == 1 ? identifier : nil
        }
      }
      for index in 0 ..< threads.count {
        let thread = threads[index]
        let identifier = try identity(thread)
        let candidate =
            ProcessThreadIdentifier(process: process, thread: identifier)
        let action = actions.action(candidate)
        if action?.operation == .resume || action?.operation == .step {
          guard selected == identifier else {
            continue
          }
          let count = try suspensions(thread)
          for _ in 0 ..< count {
            let status = thread_resume(thread)
            guard status == KERN_SUCCESS else {
              throw Debuggee.Error(mach: status, invalid: .thread)
            }
            held.append(DarwinSuspension(thread: identifier, count: -1))
          }
          continue
        }
        let status = thread_suspend(thread)
        guard status == KERN_SUCCESS else {
          throw Debuggee.Error(mach: status, invalid: .thread)
        }
        held.append(DarwinSuspension(thread: identifier, count: 1))
      }
    } catch {
      try restore(threads)
      throw error
    }
  }

  internal mutating func restore(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    guard !held.isEmpty else {
      return
    }
    let threads = try DarwinThreadList(process)
    try restore(threads)
  }

  internal mutating func restore(_ threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    var pending = held.count
    while pending > 0 {
      pending -= 1
      let record = held[pending]
      for index in 0 ..< threads.count {
        let thread = threads[index]
        guard try identity(thread) == record.thread else {
          continue
        }
        let status = if record.count > 0 {
          thread_resume(thread)
        } else {
          thread_suspend(thread)
        }
        guard status == KERN_SUCCESS else {
          throw Debuggee.Error(mach: status, invalid: .thread)
        }
        break
      }
      held.remove(at: pending)
    }
  }
}

private func awaken(_ process: pid_t) -> Bool {
  let identifier = ProcessIdentifier(rawValue: UInt64(process))
  guard let task = try? DarwinTask(identifier) else {
    return false
  }
  var resumed = false
  while true {
    var info = task_basic_info_data_t()
    let bytes = MemoryLayout<task_basic_info_data_t>.size
    let size = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(size)
    let status = withUnsafeMutablePointer(to: &info) { info in
      info.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
        task_info(task.handle, task_flavor_t(TASK_BASIC_INFO), info, &count)
      }
    }
    guard status == KERN_SUCCESS, info.suspend_count > 0 else {
      return resumed
    }
    guard task_resume(task.handle) == KERN_SUCCESS else {
      return resumed
    }
    resumed = true
  }
}

private func suspensions(_ thread: thread_t) throws(Debuggee.Error) -> Int {
  var info = thread_basic_info_data_t()
  let bytes = MemoryLayout<thread_basic_info_data_t>.size
  let size = bytes / MemoryLayout<integer_t>.size
  var count = mach_msg_type_number_t(size)
  let status = withUnsafeMutablePointer(to: &info) { info in
    info.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { info in
      thread_info(thread, thread_flavor_t(THREAD_BASIC_INFO), info, &count)
    }
  }
  guard status == KERN_SUCCESS else {
    throw Debuggee.Error(mach: status, invalid: .thread)
  }
  return Int(info.suspend_count)
}

#endif
