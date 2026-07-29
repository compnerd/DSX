// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)

internal import Darwin
internal import DSXShims

extension DarwinDebugControl {
  // MARK: - Events

  internal mutating func event(blocking: Bool = false, output: Bool = true,
                               signals _: borrowing SignalSet = SignalSet())
      throws(Debuggee.Error) -> Debuggee.Event? {
    guard let process else {
      throw .state
    }
    if output, case .some = self.output {
      return .output(process)
    }
    if let deferred {
      return try enqueue(deferred, process: process, output: output)
    }
    while true {
      if let exceptions, let record = try exceptions.next() {
        guard try exceptions.accept(record, process: process) else {
          DSX.log("rejecting foreign Darwin exception", level: .trace,
                  channel: .process)
          try exceptions.reject()
          continue
        }
        while let record = try exceptions.receive() {
          guard try exceptions.accept(record, process: process) else {
            DSX.log("rejecting foreign Darwin exception", level: .trace,
                    channel: .process)
            try exceptions.reject()
            continue
          }
        }
        var stepping: ThreadIdentifier?
        for index in 0 ..< exceptions.count {
          let thread = try identity(exceptions[index].thread)
          if steps.contains(where: { candidate in
            candidate.thread == thread
          }) {
            stepping = thread
            break
          }
        }
        let threads = try DarwinThreadList(process)
        guard events.isEmpty else {
          throw .state
        }
        var translated = false
        defer {
          if translated == false {
            events.removeAll(keepingCapacity: true)
          }
        }
        var selected = 0
        var priority = Int.min
        var replacement = false
        var stale = true
        let waiting = requested
        var signalled = false
        for index in 0 ..< exceptions.count {
          let record = exceptions[index]
          let message = "Darwin exception \(record.type) on Mach thread " +
              "\(record.thread): \(record.codes.0), \(record.codes.1)"
          DSX.log(message, level: .trace, channel: .process)
          let interrupt = waiting && record.interrupted
          if interrupt {
            signalled = true
          }
          if interrupt && obsolete {
            continue
          }
          stale = false
          let event = if interrupt {
            try Debuggee.Event(interruption: record, process: process)
          } else {
            try Debuggee.Event(record, process: process, threads: threads,
                               breakpoints: breakpoints)
          }
          let candidate = switch event {
          case .stopped(let stop) where stop.thread.thread == stepping:
            2
          case .stopped where interrupt == false:
            1
          default:
            0
          }
          if candidate > priority {
            selected = events.count
            priority = candidate
            replacement = interrupt
          }
          events.append(event)
        }
        if stale {
          try finish(threads)
          try restore(threads)
          try exceptions.reply()
          try exceptions.resume()
          requested = false
          obsolete = false
          continue
        }
        let event = events.remove(at: selected)
        translated = true
        self.replacement = replacement
        if signalled {
          requested = false
          obsolete = false
        }
        if event.completion, requested {
          obsolete = true
        }
        return try enqueue(event, process: process, output: output)
      }
      if case .none = status {
        try wait(process, output: output)
      }
      if output, case .some = self.output {
        return .output(process)
      }
      guard let status else {
        if blocking {
          _ = usleep(1_000)
          continue
        }
        return nil
      }
      self.status = nil
      if UnixWaitStatus(status).stopped {
        continue
      }
      let event = Debuggee.Event(status: status, process: process)
      if event.completion, requested {
        obsolete = true
      }
      return try enqueue(event, process: process, output: output)
    }
  }

  internal mutating func enqueue(_ event: consuming Debuggee.Event,
                                 process: ProcessIdentifier, output: Bool)
      throws(Debuggee.Error) -> Debuggee.Event {
    deferred = event
    if exceptions?.pending == true,
        steps.isEmpty == false || held.isEmpty == false {
      let threads = try DarwinThreadList(process)
      try finish(threads)
      try restore(threads)
    }
    if output, event.completion {
      if let output = try Debuggee.Output(reader) {
        self.output = output
      }
      if case .some = self.output {
        return .output(process)
      }
    }
    deferred = nil
    return deliver(consume event)
  }

  private mutating func deliver(_ event: consuming Debuggee.Event)
      -> Debuggee.Event {
    if case .exited = event {
      discard()
      process = nil
      attached = false
    }
    return consume event
  }
}

extension dsx_exception_record {
  internal var interrupted: Bool {
    switch (type, count, codes.0, codes.1) {
    case (EXC_SOFTWARE, 2..., Int64(EXC_SOFT_SIGNAL), Int64(SIGSTOP)): true
    default: false
    }
  }
}

extension DarwinDebugControl {
  private mutating func wait(_ process: ProcessIdentifier, output: Bool)
      throws(Debuggee.Error) {
    if let output = try Debuggee.Output(output ? reader : nil) {
      self.output = output
      return
    }
    let identifier = try process.native
    var status: CInt = 0
    var result: pid_t
    repeat {
      result = waitpid(identifier, &status, WNOHANG)
    } while result < 0 && errno == EINTR
    if result == 0 {
      return
    }
    guard result == identifier else {
      throw Debuggee.Error(unix: errno)
    }
    self.status = status
    DSX.log("Darwin wait status: \(status)", level: .trace, channel: .process)
  }
}

#endif
