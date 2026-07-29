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
  internal mutating func syscall(_ process: ProcessIdentifier,
                                 arguments: borrowing Span<UInt64>)
      throws(Debuggee.Error) -> UInt64 {
    guard status == nil, thread == nil else {
      throw .state
    }
    let thread = try self.thread(process)
    let address = try LinuxDebugControl.scratch(thread)
    let location = Debuggee.Address(rawValue: address)
    let native = ThreadIdentifier(rawValue: UInt64(thread))
    let identifier = ProcessThreadIdentifier(process: process, thread: native)
    let registers = try LinuxRegisterState(identifier)
    let word = try location.peek(thread, request: PTRACE_PEEKTEXT,
                                 failure: Debuggee.Error.init(unix:))
    var injected = registers.general
    try injected.prepare(arguments)
    injected.set(pc: address)
    var instruction = InlineArray<4, UInt8> { _ in 0 }
    let count = registers.general.instruction(into: &instruction)
    var replacement = word
    withUnsafeMutableBytes(of: &replacement) { replacement in
      for index in 0 ..< count {
        replacement[index] = instruction[index]
      }
    }
    try location.poke(thread, word: replacement, request: PTRACE_POKETEXT,
                      failure: Debuggee.Error.init(unix:))
    var restorable = true
    do throws(Debuggee.Error) {
      try injected.commit(thread)
      guard ptrace(PTRACE_SINGLESTEP, thread, nil, nil) == 0 else {
        throw Debuggee.Error(unix: errno)
      }
      threads[thread]?.stopped = false
      restorable = false
      var status: CInt = 0
      var retry = true
      while true {
        var waited: pid_t
        repeat {
          waited = waitpid(thread, &status, __WALL)
        } while waited < 0 && errno == EINTR
        guard waited == thread else {
          throw waited < 0 ? Debuggee.Error(unix: errno) : .state
        }
        let decoded = UnixWaitStatus(status)
        if decoded.stopped {
          threads[thread]?.stopped = true
          restorable = status >> 16 != PTRACE_EVENT_EXEC
        }
        let signal = decoded.signal
        guard decoded.stopped, status >> 16 == 0 else {
          self.status = status
          self.thread = thread
          throw .state
        }
        if signal == SIGCHLD {
          if threads[thread]?.signal == nil {
            threads[thread]?.signal = try siginfo_t(thread)
          }
          guard ptrace(PTRACE_SINGLESTEP, thread, nil, nil) == 0 else {
            self.status = status
            self.thread = thread
            throw Debuggee.Error(unix: errno)
          }
          threads[thread]?.stopped = false
          restorable = false
          continue
        }
        guard signal == SIGTRAP else {
          self.status = status
          self.thread = thread
          throw .state
        }
        let information = try siginfo_t(thread)
        let completed = try LinuxGeneralRegisters(thread)
        if information.completes(completed, at: address + UInt64(count)) {
          let result = try completed.result
          try registers.restore(address: address, word: word)
          return result
        }
        if retry, information.pending(completed, at: address) {
          retry = false
          // Leaving a kernel event-stop can report a step before the injected
          // instruction executes. The kernel may also replace the return
          // register on syscall exit, so restore every injected argument.
          try injected.commit(thread)
          guard ptrace(PTRACE_SINGLESTEP, thread, nil, nil) == 0 else {
            self.status = status
            self.thread = thread
            throw Debuggee.Error(unix: errno)
          }
          threads[thread]?.stopped = false
          restorable = false
          continue
        }
        self.status = status
        self.thread = thread
        let code = information.si_code
        let program = completed.program
        DSX.log("syscall stopped before completion: code=\(code) pc=\(program)",
                level: .trace, channel: .process)
        throw .state
      }
    } catch {
      let failure = error
      guard restorable else {
        throw failure
      }
      do {
        try registers.restore(address: address, word: word)
      } catch {
        DSX.log("failed to restore debuggee after syscall: \(error)",
                level: .error, channel: .process)
      }
      throw failure
    }
  }

  internal func thread(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> pid_t {
    let leader = try process.native
    guard self.process == process || children.contains(leader) else {
      throw .process
    }
    if threads[leader]?.stopped == true, threads[leader]?.process == process {
      return leader
    }
    var selected: pid_t?
    for (thread, state) in threads
        where state.process == process && state.stopped {
      if let current = selected {
        selected = min(current, thread)
      } else {
        selected = thread
      }
    }
    guard let selected else {
      throw .state
    }
    return selected
  }

  private static func scratch(_ process: pid_t) throws(Debuggee.Error)
      -> UInt64 {
    let bytes = try LinuxProcFS.contents("/proc/\(process)/maps")
    var maps = LinuxMemoryMapReader(bytes.span)
    while let map = maps.next() {
      if map.executable, map.shared == false {
        return map.start.rawValue
      }
    }
    throw .memory
  }
}

extension LinuxRegisterState {
  fileprivate func restore(address: UInt64, word: CLong) throws(Debuggee.Error) {
    do {
      let location = Debuggee.Address(rawValue: address)
      try location.poke(thread, word: word, request: PTRACE_POKETEXT,
                        failure: Debuggee.Error.init(unix:))
    } catch {
      do {
        try restore()
      } catch {
        DSX.log("failed to restore debuggee registers: \(error)", level: .error,
                channel: .process)
      }
      throw error
    }
    try restore()
  }
}
#endif
