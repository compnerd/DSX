// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

private typealias Failure = Debuggee.Error

internal struct LinuxRegisterState: Sendable {
  internal static func synchronize(_: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
  }

  internal let thread: pid_t
  internal var general: LinuxGeneralRegisters
  internal var floating: LinuxFloatingRegisters
#if arch(arm64)
  internal var tls: UInt64
  internal var masks: InlineArray<2, UInt64>?
  internal var scalable: LinuxScalableRegisters?
#endif

  internal init(_ identifier: ProcessThreadIdentifier) throws(Debuggee.Error) {
    let thread = try identifier.native
    self.thread = thread
    let failure = Debuggee.Error.init(register:)
    general = try LinuxGeneralRegisters(thread, failure: failure)
#if arch(arm64)
    scalable = try LinuxScalableRegisters(thread)
    floating = if scalable?.length == 0 {
      LinuxFloatingRegisters()
    } else {
      try LinuxFloatingRegisters(thread)
    }
    tls = 0
    _ = try withUnsafeMutableBytes(of: &tls, { bytes throws(Failure) in
      try bytes.transfer(PTRACE_GETREGSET, note: NT_ARM_TLS, thread: thread)
    })
    var masks = InlineArray<2, UInt64> { _ in 0 }
    let available: Int? =
        try? withUnsafeMutableBytes(of: &masks, { bytes throws(Failure) in
          try bytes.transfer(PTRACE_GETREGSET, note: NT_ARM_PAC_MASK,
                             thread: thread)
        })
    self.masks = available == nil ? nil : masks
#else
    floating = try LinuxFloatingRegisters(thread)
#endif
  }

  internal consuming func commit(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    guard try thread == identifier.native else {
      throw .thread
    }
    return try commit()
  }

  private consuming func commit() throws(Debuggee.Error) {
    let thread = thread
    try general.commit(thread, failure: Debuggee.Error.init(register:))
#if arch(arm64)
    if scalable == nil {
      try floating.commit(thread)
    }
    _ = try withUnsafeMutableBytes(of: &tls, { bytes throws(Failure) in
      try bytes.transfer(PTRACE_SETREGSET, note: NT_ARM_TLS, thread: thread)
    })
    try scalable?.commit(thread)
#else
    try floating.commit(thread)
#endif
  }

  internal consuming func restore() throws(Debuggee.Error) {
#if arch(arm64)
    scalable?.preserve()
#endif
    try commit()
  }
}

extension LinuxGeneralRegisters {
  internal var result: UInt64 {
    get throws(Debuggee.Error) {
      let value = returned
      guard value < UInt64.max - 4094 else {
        let code = CInt(0 &- value)
        throw Debuggee.Error(unix: code, invalid: .memory)
      }
      return value & UInt64(UInt.max)
    }
  }

  internal init(_ thread: pid_t,
                failure: (CInt) -> Debuggee.Error = Debuggee.Error.init(unix:))
      throws(Debuggee.Error) {
    self.init()
    _ = try withUnsafeMutableBytes(of: &self, { bytes throws(Failure) in
      try bytes.transfer(PTRACE_GETREGSET, note: NT_PRSTATUS, thread: thread,
                         failure: failure)
    })
  }

  internal func commit(_ thread: pid_t, failure: (CInt) -> Debuggee.Error =
                           Debuggee.Error.init(unix:)) throws(Debuggee.Error) {
    var registers = self
    _ = try withUnsafeMutableBytes(of: &registers, { bytes throws(Failure) in
      try bytes.transfer(PTRACE_SETREGSET, note: NT_PRSTATUS, thread: thread,
                         failure: failure)
    })
  }
}

#if !arch(i386)
extension LinuxFloatingRegisters {
  internal init(_ thread: pid_t) throws(Debuggee.Error) {
    self.init()
    _ = try withUnsafeMutableBytes(of: &self, { bytes throws(Failure) in
#if arch(arm)
      try bytes.transfer(PTRACE_GETREGSET, note: NT_ARM_VFP, thread: thread)
#else
      try bytes.transfer(PTRACE_GETREGSET, note: NT_FPREGSET, thread: thread)
#endif
    })
  }

  internal mutating func commit(_ thread: pid_t) throws(Debuggee.Error) {
    _ = try withUnsafeMutableBytes(of: &self, { bytes throws(Failure) in
#if arch(arm)
      try bytes.transfer(PTRACE_SETREGSET, note: NT_ARM_VFP, thread: thread)
#else
      try bytes.transfer(PTRACE_SETREGSET, note: NT_FPREGSET, thread: thread)
#endif
    })
  }
}
#endif
#endif
