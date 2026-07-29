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

extension LinuxRegisters {
  internal static func read(_ state: borrowing LinuxRegisterState,
                            register: RegisterIdentifier,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let value: UInt64? = switch register.rawValue {
    case 0: state.general.rax
    case 1: state.general.rbx
    case 2: state.general.rcx
    case 3: state.general.rdx
    case 4: state.general.rsi
    case 5: state.general.rdi
    case 6: state.general.rbp
    case 7: state.general.stack
    case 8: state.general.r8
    case 9: state.general.r9
    case 10: state.general.r10
    case 11: state.general.r11
    case 12: state.general.r12
    case 13: state.general.r13
    case 14: state.general.r14
    case 15: state.general.r15
    case 16: state.general.program
    case 17: state.general.flags
    case 18: state.general.code
    case 19: state.general.segment
    case 20: state.general.data
    case 21: state.general.extra
    case 22: state.general.fs
    case 23: state.general.gs
    default: nil
    }
    if let value {
      let size = register.rawValue < 17 ? 8 : 4
      return try RegisterBytes.append(value, size: size, into: &output)
    }
    switch register.rawValue {
    case 24 ... 31:
      let offset = Int(register.rawValue - 24) * 16
      try RegisterBytes.append(state.floating.stack, offset: offset, size: 10,
                               into: &output)
    case 32:
      try RegisterBytes.extend(state.floating.control, size: 4, into: &output)
    case 33:
      try RegisterBytes.extend(state.floating.status, size: 4, into: &output)
    case 34:
      try RegisterBytes.extend(state.floating.tag, size: 4, into: &output)
    case 35:
      try RegisterBytes.append(UInt32(0), size: 4, into: &output)
    case 36:
      try RegisterBytes.append(state.floating.instruction, size: 4,
                               into: &output)
    case 37:
      try RegisterBytes.append(UInt32(0), size: 4, into: &output)
    case 38:
      try RegisterBytes.append(state.floating.data, size: 4, into: &output)
    case 39:
      try RegisterBytes.extend(state.floating.opcode, size: 4, into: &output)
    case 40 ... 55:
      let offset = Int(register.rawValue - 40) * 16
      try RegisterBytes.append(state.floating.vector, offset: offset, size: 16,
                               into: &output)
    case 56:
      try RegisterBytes.append(state.floating.mxcsr, size: 4, into: &output)
    default:
      throw .register
    }
  }

  internal static func write(_ state: inout LinuxRegisterState,
                             register: RegisterIdentifier,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0: state.general.rax = try RegisterBytes.value(bytes, as: UInt64.self)
    case 1: state.general.rbx = try RegisterBytes.value(bytes, as: UInt64.self)
    case 2: state.general.rcx = try RegisterBytes.value(bytes, as: UInt64.self)
    case 3: state.general.rdx = try RegisterBytes.value(bytes, as: UInt64.self)
    case 4: state.general.rsi = try RegisterBytes.value(bytes, as: UInt64.self)
    case 5: state.general.rdi = try RegisterBytes.value(bytes, as: UInt64.self)
    case 6: state.general.rbp = try RegisterBytes.value(bytes, as: UInt64.self)
    case 7:
      state.general.stack = try RegisterBytes.value(bytes, as: UInt64.self)
    case 8: state.general.r8 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 9: state.general.r9 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 10:
      state.general.r10 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 11:
      state.general.r11 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 12:
      state.general.r12 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 13:
      state.general.r13 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 14:
      state.general.r14 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 15:
      state.general.r15 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 16:
      state.general.program = try RegisterBytes.value(bytes, as: UInt64.self)
    case 17:
      state.general.flags =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 18:
      state.general.code =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 19:
      state.general.segment =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 20:
      state.general.data =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 21:
      state.general.extra =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 22:
      state.general.fs = try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 23:
      state.general.gs = try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 24 ... 31:
      let offset = Int(register.rawValue - 24) * 16
      try RegisterBytes.write(bytes, offset: offset, to: &state.floating.stack)
    case 32:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.control)
    case 33:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.status)
    case 34:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.tag)
    case 35, 37:
      guard bytes.count == 4 else {
        throw .register
      }
    case 36:
      state.floating.instruction =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 38:
      state.floating.data =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 39:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.opcode)
    case 40 ... 55:
      let offset = Int(register.rawValue - 40) * 16
      try RegisterBytes.write(bytes, offset: offset, to: &state.floating.vector)
    case 56:
      state.floating.mxcsr = try RegisterBytes.value(bytes, as: UInt32.self)
    default:
      throw .register
    }
  }
}
#endif
