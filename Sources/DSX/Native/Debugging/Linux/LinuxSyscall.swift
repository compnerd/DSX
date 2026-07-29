// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

extension LinuxDebugControl {
  internal mutating func syscall(_ process: ProcessIdentifier,
                                 arguments: borrowing Span<UInt64>)
      throws(Debuggee.Error) -> UInt64 {
    guard self.process == process else {
      throw .state
    }
    if case .some = status {
      throw .state
    }
    if case .some = thread {
      throw .state
    }
    let process = try process.native
    let thread = stopped.contains(process) ? process : stopped.first
    guard let thread else {
      throw .state
    }
    let address = try LinuxDebugControl.scratch(thread)
    let registers = try LinuxDebugControl.registers(thread)
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
    do throws(Debuggee.Error) {
      try LinuxDebugControl.registers(thread, value: &injected)
      _ = stopped.remove(thread)
      defer { _ = stopped.insert(thread) }
      guard ptrace(PTRACE_SINGLESTEP, thread, nil, nil) == 0 else {
        throw UnixDebugProcess.failure(errno)
      }
      var status: CInt = 0
      var waited: pid_t
      repeat {
        waited = waitpid(thread, &status, __WALL)
      } while waited < 0 && errno == EINTR
      guard waited == thread, UnixWaitStatus.stopped(status),
          UnixWaitStatus.signal(status) == SIGTRAP else {
        throw waited < 0 ? UnixDebugProcess.failure(errno) : .state
      }
      let completed = try LinuxDebugControl.registers(thread)
      let raw = ABI.result(completed)
      let result = try LinuxDebugControl.validate(raw)
      try LinuxDebugControl.restore(thread, address: address, word: word,
                                    registers: registers)
      return result
    } catch {
      let failure = error
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

  private static func scratch(_ process: pid_t) throws(Debuggee.Error)
      -> UInt64 {
    let bytes = try LinuxProcFS.contents("/proc/\(process)/maps")
    var maps = LinuxMemoryMapReader(bytes.span)
    while let map = maps.next() {
      if map.executable, !map.shared {
        return map.start.rawValue
      }
    }
    throw .memory
  }

  private static func registers(_ thread: pid_t) throws(Debuggee.Error)
      -> LinuxGeneralRegisters {
    var registers = LinuxGeneralRegisters()
    try transfer(PTRACE_GETREGSET, thread: thread, value: &registers)
    return registers
  }

  private static func registers(_ thread: pid_t,
                                value: inout LinuxGeneralRegisters)
      throws(Debuggee.Error) {
    try transfer(PTRACE_SETREGSET, thread: thread, value: &value)
  }

  private static func transfer<Value>(_ request: CInt, thread: pid_t,
                                      value: inout Value)
      throws(Debuggee.Error) {
    var vector =
        iovec(iov_base: nil, iov_len: numericCast(MemoryLayout<Value>.size))
    let result = withUnsafeMutablePointer(to: &value) { value in
      vector.iov_base = UnsafeMutableRawPointer(value)
      return withUnsafeMutablePointer(to: &vector) { vector in
        ptrace(request, thread,
               UnsafeMutableRawPointer(bitPattern: NT_PRSTATUS),
               UnsafeMutableRawPointer(vector))
      }
    }
    let complete = vector.iov_len == numericCast(MemoryLayout<Value>.size)
    guard result == 0, complete else {
      throw result == 0 ? .register : UnixDebugProcess.failure(errno)
    }
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
      var registers = registers
      do {
        try LinuxDebugControl.registers(thread, value: &registers)
      } catch {
        DSX.log("failed to restore debuggee registers: \(error)", level: .error,
                channel: .process)
      }
      throw error
    }
    var registers = registers
    try LinuxDebugControl.registers(thread, value: &registers)
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
