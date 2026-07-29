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
    let registers = try LinuxGeneralRegisters(thread)
    let word = try LinuxDebugControl.peek(thread, address: address)
    var injected = registers
    try ABI.prepare(arguments, registers: &injected)
    ABI.program(address, registers: &injected)
    var instruction = InlineArray<4, UInt8> { _ in 0 }
    let count = ABI.instruction(registers, into: &instruction)
    var replacement = word
    withUnsafeMutableBytes(of: &replacement) { replacement in
      for index in 0 ..< count {
        replacement[index] = instruction[index]
      }
    }
    try LinuxDebugControl.poke(thread, address: address, word: replacement)
    var restorable = true
    do throws(Debuggee.Error) {
      try injected.commit(thread)
      guard ptrace(PTRACE_SINGLESTEP, thread, nil, nil) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      _ = stopped.remove(thread)
      restorable = false
      var status: CInt = 0
      var waited: pid_t
      repeat {
        waited = waitpid(thread, &status, __WALL)
      } while waited < 0 && errno == EINTR
      guard waited == thread else {
        throw waited < 0 ? UnixDebugProcess.failure(errno) : .state
      }
      self.status = status
      self.thread = thread
      if UnixWaitStatus.stopped(status) {
        stopped.insert(thread)
        restorable = ptraceevent(status) != PTRACE_EVENT_EXEC
      }
      guard UnixWaitStatus.stopped(status), ptraceevent(status) == 0,
          UnixWaitStatus.signal(status) == SIGTRAP else {
        throw .state
      }
      let information = try siginfo_t(thread)
      let completed = try LinuxGeneralRegisters(thread)
      guard information.completes(completed, at: address + UInt64(count)) else {
        throw .state
      }
      self.status = nil
      self.thread = nil
      let raw = ABI.result(completed)
      let result = try LinuxDebugControl.validate(raw)
      try LinuxDebugControl.restore(thread, address: address, word: word,
                                    registers: registers)
      return result
    } catch {
      let failure = error
      guard restorable else {
        throw failure
      }
      do {
        try LinuxDebugControl.restore(thread, address: address, word: word,
                                      registers: registers)
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
    if stopped.contains(leader), owners[leader] == process {
      return leader
    }
    guard let thread = stopped.first(where: { owners[$0] == process }) else {
      throw .state
    }
    return thread
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

  private static func peek(_ thread: pid_t, address: UInt64)
      throws(Debuggee.Error) -> CLong {
    errno = 0
    let value = try Debuggee.Address(rawValue: address).native
    let address = UnsafeMutableRawPointer(bitPattern: value)
    let word = ptrace(PTRACE_PEEKTEXT, thread, address, nil)
    if word == -1, errno != 0 {
      throw UnixDebugProcess.failure(errno)
    }
    return word
  }

  private static func poke(_ thread: pid_t, address: UInt64, word: CLong)
      throws(Debuggee.Error) {
    let value = try Debuggee.Address(rawValue: address).native
    let address = UnsafeMutableRawPointer(bitPattern: value)
    let data = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: word))
    guard ptrace(PTRACE_POKETEXT, thread, address, data) == 0 else {
      throw UnixDebugProcess.failure(errno)
    }
  }

  private static func restore(_ thread: pid_t, address: UInt64, word: CLong,
                              registers: LinuxGeneralRegisters)
      throws(Debuggee.Error) {
    do {
      try poke(thread, address: address, word: word)
    } catch {
      do {
        try registers.commit(thread)
      } catch {
        DSX.log("failed to restore debuggee registers: \(error)", level: .error,
                channel: .process)
      }
      throw error
    }
    try registers.commit(thread)
  }

  internal static func validate(_ result: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    guard result < UInt64.max - 4094 else {
      let code = CInt(0 &- result)
      throw UnixError.debuggee(code, invalid: .memory)
    }
    return result & UInt64(UInt.max)
  }
}
#endif
