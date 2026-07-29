// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(i386)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif
internal import DSXShims

internal struct LinuxGeneralRegisters: Sendable {
  internal var ebx: UInt32 = 0
  internal var ecx: UInt32 = 0
  internal var edx: UInt32 = 0
  internal var esi: UInt32 = 0
  internal var edi: UInt32 = 0
  internal var ebp: UInt32 = 0
  internal var eax: UInt32 = 0
  internal var data: UInt32 = 0
  internal var extra: UInt32 = 0
  internal var fs: UInt32 = 0
  internal var gs: UInt32 = 0
  internal var origin: UInt32 = 0
  internal var program: UInt32 = 0
  internal var code: UInt32 = 0
  internal var flags: UInt32 = 0
  internal var stack: UInt32 = 0
  internal var segment: UInt32 = 0
}

internal struct LinuxFloatingRegisters: Sendable {
  internal var control: UInt16 = 0
  internal var status: UInt16 = 0
  internal var tag: UInt16 = 0
  internal var opcode: UInt16 = 0
  internal var program: UInt32 = 0
  internal var code: UInt32 = 0
  internal var data: UInt32 = 0
  internal var segment: UInt32 = 0
  internal var mxcsr: UInt32 = 0
  internal var reserved: UInt32 = 0
  internal var stack: InlineArray<32, UInt32>
  internal var vector: InlineArray<32, UInt32>
  internal var padding: InlineArray<56, UInt32>

  internal init() {
    stack = InlineArray<32, UInt32> { _ in 0 }
    vector = InlineArray<32, UInt32> { _ in 0 }
    padding = InlineArray<56, UInt32> { _ in 0 }
  }

  internal init(_ thread: pid_t) throws(Debuggee.Error) {
    self.init()
    try transfer(PTRACE_GETFPXREGS, thread: thread)
  }

  internal mutating func commit(_ thread: pid_t) throws(Debuggee.Error) {
    try transfer(PTRACE_SETFPXREGS, thread: thread)
  }

  /// This is the 512-byte FXSAVE layout, not the variable-size XSAVE regset.
  private mutating func transfer(_ request: CInt, thread: pid_t)
      throws(Debuggee.Error) {
    let result = withUnsafeMutablePointer(to: &self) {
      ptrace(request, thread, nil, UnsafeMutableRawPointer($0))
    }
    guard result == 0 else {
      throw Debuggee.Error(register: errno)
    }
  }
}

extension LinuxRegisterState {
  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let value: UInt32? = switch register.rawValue {
    case 0: general.eax
    case 1: general.ecx
    case 2: general.edx
    case 3: general.ebx
    case 4: general.stack
    case 5: general.ebp
    case 6: general.esi
    case 7: general.edi
    case 8: general.program
    case 9: general.flags
    case 10: general.code
    case 11: general.segment
    case 12: general.data
    case 13: general.extra
    case 14: general.fs
    case 15: general.gs
    default: nil
    }
    if let value {
      return try output.append(value, size: 4)
    }
    switch register.rawValue {
    case 16 ... 23:
      let offset = Int(register.rawValue - 16) * 16
      try output.append(floating.stack, offset: offset, size: 10)
    case 24:
      try output.extend(floating.control, size: 4)
    case 25:
      try output.extend(floating.status, size: 4)
    case 26:
      try output.extend(floating.tag, size: 4)
    case 27:
      try output.append(floating.code, size: 4)
    case 28:
      try output.append(floating.program, size: 4)
    case 29:
      try output.append(floating.segment, size: 4)
    case 30:
      try output.append(floating.data, size: 4)
    case 31:
      try output.extend(floating.opcode, size: 4)
    case 32 ... 39:
      let offset = Int(register.rawValue - 32) * 16
      try output.append(floating.vector, offset: offset, size: 16)
    case 40:
      try output.append(floating.mxcsr, size: 4)
    default:
      throw .register
    }
  }

  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0: general.eax = try bytes.register(as: UInt32.self)
    case 1: general.ecx = try bytes.register(as: UInt32.self)
    case 2: general.edx = try bytes.register(as: UInt32.self)
    case 3: general.ebx = try bytes.register(as: UInt32.self)
    case 4:
      general.stack = try bytes.register(as: UInt32.self)
    case 5: general.ebp = try bytes.register(as: UInt32.self)
    case 6: general.esi = try bytes.register(as: UInt32.self)
    case 7: general.edi = try bytes.register(as: UInt32.self)
    case 8:
      try general.set(pc: UInt64(bytes.register(as: UInt32.self)))
    case 9:
      general.flags = try bytes.register(as: UInt32.self)
    case 10:
      general.code = try bytes.register(as: UInt32.self)
    case 11:
      general.segment = try bytes.register(as: UInt32.self)
    case 12:
      general.data = try bytes.register(as: UInt32.self)
    case 13:
      general.extra = try bytes.register(as: UInt32.self)
    case 14:
      general.fs = try bytes.register(as: UInt32.self)
    case 15:
      general.gs = try bytes.register(as: UInt32.self)
    case 16 ... 23:
      let offset = Int(register.rawValue - 16) * 16
      try bytes.write(offset: offset, to: &floating.stack)
    case 24:
      try bytes.narrow(size: 4, to: &floating.control)
    case 25:
      try bytes.narrow(size: 4, to: &floating.status)
    case 26:
      try bytes.narrow(size: 4, to: &floating.tag)
    case 27:
      floating.code = try bytes.register(as: UInt32.self)
    case 28:
      floating.program = try bytes.register(as: UInt32.self)
    case 29:
      floating.segment = try bytes.register(as: UInt32.self)
    case 30:
      floating.data = try bytes.register(as: UInt32.self)
    case 31:
      try bytes.narrow(size: 4, to: &floating.opcode)
    case 32 ... 39:
      let offset = Int(register.rawValue - 32) * 16
      try bytes.write(offset: offset, to: &floating.vector)
    case 40:
      floating.mxcsr = try bytes.register(as: UInt32.self)
    default:
      throw .register
    }
  }
}
#endif
