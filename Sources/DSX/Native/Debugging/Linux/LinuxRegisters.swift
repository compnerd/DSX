// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

internal struct LinuxRegisterState: Sendable {
  internal let thread: pid_t
  internal var general: LinuxGeneralRegisters
  internal var floating: LinuxFloatingRegisters
#if arch(arm64)
  internal var tls: UInt64
#endif

#if arch(arm64)
  internal init(thread: pid_t, general: LinuxGeneralRegisters,
                floating: LinuxFloatingRegisters, tls: UInt64) {
    self.thread = thread
    self.general = general
    self.floating = floating
    self.tls = tls
  }
#else
  internal init(thread: pid_t, general: LinuxGeneralRegisters,
                floating: LinuxFloatingRegisters) {
    self.thread = thread
    self.general = general
    self.floating = floating
  }
#endif
}

internal enum LinuxRegisters {
  internal typealias State = LinuxRegisterState

  internal static func synchronize(_: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
  }

  internal static func snapshot(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> LinuxRegisterState {
    let thread = try identifier.native
    var general = LinuxGeneralRegisters()
    try transfer(PTRACE_GETREGSET, note: NT_PRSTATUS, thread: thread,
                 value: &general)
    var floating = LinuxFloatingRegisters()
#if arch(arm)
    try transfer(PTRACE_GETREGSET, note: NT_ARM_VFP, thread: thread,
                 value: &floating)
#elseif arch(i386)
    try transfer(PTRACE_GETREGSET, note: NT_X86_XSTATE, thread: thread,
                 value: &floating)
#else
    try transfer(PTRACE_GETREGSET, note: NT_FPREGSET, thread: thread,
                 value: &floating)
#endif
#if arch(arm64)
    var tls: UInt64 = 0
    try transfer(PTRACE_GETREGSET, note: NT_ARM_TLS, thread: thread,
                 value: &tls)
    return LinuxRegisterState(thread: thread, general: general,
                              floating: floating, tls: tls)
#else
    return LinuxRegisterState(thread: thread, general: general,
                              floating: floating)
#endif
  }

  internal static func syscall(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> UInt64 {
    var general = LinuxGeneralRegisters()
    try transfer(PTRACE_GETREGSET, note: NT_PRSTATUS,
                 thread: identifier.native, value: &general)
#if arch(arm64)
    return general.values[8]
#elseif arch(arm)
    return UInt64(general.values[7])
#elseif arch(i386) || arch(x86_64)
    return UInt64(general.origin)
#endif
  }

  internal static func commit(_ state: consuming LinuxRegisterState,
                              thread identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    var state = consume state
    let thread = try identifier.native
    guard state.thread == thread else {
      throw .thread
    }
    try transfer(PTRACE_SETREGSET, note: NT_PRSTATUS, thread: state.thread,
                 value: &state.general)
#if arch(arm)
    try transfer(PTRACE_SETREGSET, note: NT_ARM_VFP, thread: state.thread,
                 value: &state.floating)
#elseif arch(i386)
    try transfer(PTRACE_SETREGSET, note: NT_X86_XSTATE, thread: state.thread,
                 value: &state.floating)
#else
    try transfer(PTRACE_SETREGSET, note: NT_FPREGSET, thread: state.thread,
                 value: &state.floating)
#endif
#if arch(arm64)
    try transfer(PTRACE_SETREGSET, note: NT_ARM_TLS, thread: state.thread,
                 value: &state.tls)
#endif
  }

  internal static func transfer<Value>(_ request: CInt, note: Int,
                                       thread: pid_t, value: inout Value,
                                       failure: (CInt) -> Debuggee.Error =
                                           UnixError.register)
      throws(Debuggee.Error) {
    var vector =
        iovec(iov_base: nil, iov_len: numericCast(MemoryLayout<Value>.size))
    let result = withUnsafeMutablePointer(to: &value) { value in
      vector.iov_base = UnsafeMutableRawPointer(value)
      return withUnsafeMutablePointer(to: &vector) { vector in
        ptrace(request, thread, UnsafeMutableRawPointer(bitPattern: note),
               UnsafeMutableRawPointer(vector))
      }
    }
    guard result == 0 else {
      throw failure(errno)
    }
    guard vector.iov_len == numericCast(MemoryLayout<Value>.size) else {
      throw .register
    }
  }
}

extension LinuxGeneralRegisters {
  internal init(_ thread: pid_t) throws(Debuggee.Error) {
    self.init()
    try LinuxRegisters.transfer(PTRACE_GETREGSET, note: NT_PRSTATUS,
                                thread: thread, value: &self,
                                failure: UnixDebugProcess.failure)
  }

  internal func commit(_ thread: pid_t) throws(Debuggee.Error) {
    var registers = self
    try LinuxRegisters.transfer(PTRACE_SETREGSET, note: NT_PRSTATUS,
                                thread: thread, value: &registers,
                                failure: UnixDebugProcess.failure)
  }
}
#endif
