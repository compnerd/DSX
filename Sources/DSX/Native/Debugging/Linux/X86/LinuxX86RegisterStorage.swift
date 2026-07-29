// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(x86_64)
internal struct LinuxGeneralRegisters: Sendable {
  internal var r15: UInt64 = 0
  internal var r14: UInt64 = 0
  internal var r13: UInt64 = 0
  internal var r12: UInt64 = 0
  internal var rbp: UInt64 = 0
  internal var rbx: UInt64 = 0
  internal var r11: UInt64 = 0
  internal var r10: UInt64 = 0
  internal var r9: UInt64 = 0
  internal var r8: UInt64 = 0
  internal var rax: UInt64 = 0
  internal var rcx: UInt64 = 0
  internal var rdx: UInt64 = 0
  internal var rsi: UInt64 = 0
  internal var rdi: UInt64 = 0
  internal var origin: UInt64 = 0
  internal var program: UInt64 = 0
  internal var code: UInt64 = 0
  internal var flags: UInt64 = 0
  internal var stack: UInt64 = 0
  internal var segment: UInt64 = 0
  internal var fsbase: UInt64 = 0
  internal var gsbase: UInt64 = 0
  internal var data: UInt64 = 0
  internal var extra: UInt64 = 0
  internal var fs: UInt64 = 0
  internal var gs: UInt64 = 0

}

internal struct LinuxFloatingRegisters: Sendable {
  internal var control: UInt16 = 0
  internal var status: UInt16 = 0
  internal var tag: UInt16 = 0
  internal var opcode: UInt16 = 0
  internal var instruction: UInt64 = 0
  internal var data: UInt64 = 0
  internal var mxcsr: UInt32 = 0
  internal var mask: UInt32 = 0
  internal var stack: InlineArray<32, UInt32>
  internal var vector: InlineArray<64, UInt32>
  internal var padding: InlineArray<24, UInt32>

  internal init() {
    stack = InlineArray<32, UInt32> { _ in 0 }
    vector = InlineArray<64, UInt32> { _ in 0 }
    padding = InlineArray<24, UInt32> { _ in 0 }
  }
}

extension LinuxRegisterState {
  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let value: UInt64? = switch register.rawValue {
    case 0: general.rax
    case 1: general.rbx
    case 2: general.rcx
    case 3: general.rdx
    case 4: general.rsi
    case 5: general.rdi
    case 6: general.rbp
    case 7: general.stack
    case 8: general.r8
    case 9: general.r9
    case 10: general.r10
    case 11: general.r11
    case 12: general.r12
    case 13: general.r13
    case 14: general.r14
    case 15: general.r15
    case 16: general.program
    case 17: general.flags
    case 18: general.code
    case 19: general.segment
    case 20: general.data
    case 21: general.extra
    case 22: general.fs
    case 23: general.gs
    case 57: general.fsbase
    case 58: general.gsbase
    default: nil
    }
    if let value {
      let size = (17 ... 23).contains(register.rawValue) ? 4 : 8
      return try output.append(value, size: size)
    }
    switch register.rawValue {
    case 24 ... 31:
      let offset = Int(register.rawValue - 24) * 16
      try output.append(floating.stack, offset: offset, size: 10)
    case 32:
      try output.extend(floating.control, size: 4)
    case 33:
      try output.extend(floating.status, size: 4)
    case 34:
      try output.extend(floating.tag, size: 4)
    case 35:
      try output.append(UInt32(0), size: 4)
    case 36:
      try output.append(floating.instruction, size: 4)
    case 37:
      try output.append(UInt32(0), size: 4)
    case 38:
      try output.append(floating.data, size: 4)
    case 39:
      try output.extend(floating.opcode, size: 4)
    case 40 ... 55:
      let offset = Int(register.rawValue - 40) * 16
      try output.append(floating.vector, offset: offset, size: 16)
    case 56:
      try output.append(floating.mxcsr, size: 4)
    default:
      throw .register
    }
  }

  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0: general.rax = try bytes.register(as: UInt64.self)
    case 1: general.rbx = try bytes.register(as: UInt64.self)
    case 2: general.rcx = try bytes.register(as: UInt64.self)
    case 3: general.rdx = try bytes.register(as: UInt64.self)
    case 4: general.rsi = try bytes.register(as: UInt64.self)
    case 5: general.rdi = try bytes.register(as: UInt64.self)
    case 6: general.rbp = try bytes.register(as: UInt64.self)
    case 7:
      general.stack = try bytes.register(as: UInt64.self)
    case 8: general.r8 = try bytes.register(as: UInt64.self)
    case 9: general.r9 = try bytes.register(as: UInt64.self)
    case 10:
      general.r10 = try bytes.register(as: UInt64.self)
    case 11:
      general.r11 = try bytes.register(as: UInt64.self)
    case 12:
      general.r12 = try bytes.register(as: UInt64.self)
    case 13:
      general.r13 = try bytes.register(as: UInt64.self)
    case 14:
      general.r14 = try bytes.register(as: UInt64.self)
    case 15:
      general.r15 = try bytes.register(as: UInt64.self)
    case 16:
      try general.set(pc: bytes.register(as: UInt64.self))
    case 17:
      general.flags = try UInt64(bytes.register(as: UInt32.self))
    case 18:
      general.code = try UInt64(bytes.register(as: UInt32.self))
    case 19:
      general.segment = try UInt64(bytes.register(as: UInt32.self))
    case 20:
      general.data = try UInt64(bytes.register(as: UInt32.self))
    case 21:
      general.extra = try UInt64(bytes.register(as: UInt32.self))
    case 22:
      general.fs = try UInt64(bytes.register(as: UInt32.self))
    case 23:
      general.gs = try UInt64(bytes.register(as: UInt32.self))
    case 24 ... 31:
      let offset = Int(register.rawValue - 24) * 16
      try bytes.write(offset: offset, to: &floating.stack)
    case 32:
      try bytes.narrow(size: 4, to: &floating.control)
    case 33:
      try bytes.narrow(size: 4, to: &floating.status)
    case 34:
      try bytes.narrow(size: 4, to: &floating.tag)
    case 35, 37:
      guard bytes.count == 4 else {
        throw .register
      }
    case 36:
      floating.instruction = try UInt64(bytes.register(as: UInt32.self))
    case 38:
      floating.data = try UInt64(bytes.register(as: UInt32.self))
    case 39:
      try bytes.narrow(size: 4, to: &floating.opcode)
    case 40 ... 55:
      let offset = Int(register.rawValue - 40) * 16
      try bytes.write(offset: offset, to: &floating.vector)
    case 56:
      floating.mxcsr = try bytes.register(as: UInt32.self)
    case 57:
      general.fsbase = try bytes.register(as: UInt64.self)
    case 58:
      general.gsbase = try bytes.register(as: UInt64.self)
    default:
      throw .register
    }
  }
}
#endif
