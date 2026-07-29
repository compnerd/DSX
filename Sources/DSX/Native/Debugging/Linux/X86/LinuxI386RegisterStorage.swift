// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(i386)
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
}

extension LinuxRegisters {
  internal static func read(_ state: borrowing LinuxRegisterState,
                            register: RegisterIdentifier,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let value: UInt32? = switch register.rawValue {
    case 0: state.general.eax
    case 1: state.general.ecx
    case 2: state.general.edx
    case 3: state.general.ebx
    case 4: state.general.stack
    case 5: state.general.ebp
    case 6: state.general.esi
    case 7: state.general.edi
    case 8: state.general.program
    case 9: state.general.flags
    case 10: state.general.code
    case 11: state.general.segment
    case 12: state.general.data
    case 13: state.general.extra
    case 14: state.general.fs
    case 15: state.general.gs
    default: nil
    }
    if let value {
      return try RegisterBytes.append(value, size: 4, into: &output)
    }
    switch register.rawValue {
    case 16 ... 23:
      let offset = Int(register.rawValue - 16) * 16
      try RegisterBytes.append(state.floating.stack, offset: offset, size: 10,
                               into: &output)
    case 24:
      try RegisterBytes.extend(state.floating.control, size: 4, into: &output)
    case 25:
      try RegisterBytes.extend(state.floating.status, size: 4, into: &output)
    case 26:
      try RegisterBytes.extend(state.floating.tag, size: 4, into: &output)
    case 27:
      try RegisterBytes.append(state.floating.code, size: 4, into: &output)
    case 28:
      try RegisterBytes.append(state.floating.program, size: 4, into: &output)
    case 29:
      try RegisterBytes.append(state.floating.segment, size: 4, into: &output)
    case 30:
      try RegisterBytes.append(state.floating.data, size: 4, into: &output)
    case 31:
      try RegisterBytes.extend(state.floating.opcode, size: 4, into: &output)
    case 32 ... 39:
      let offset = Int(register.rawValue - 32) * 16
      try RegisterBytes.append(state.floating.vector, offset: offset, size: 16,
                               into: &output)
    case 40:
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
    case 0: state.general.eax = try RegisterBytes.value(bytes, as: UInt32.self)
    case 1: state.general.ecx = try RegisterBytes.value(bytes, as: UInt32.self)
    case 2: state.general.edx = try RegisterBytes.value(bytes, as: UInt32.self)
    case 3: state.general.ebx = try RegisterBytes.value(bytes, as: UInt32.self)
    case 4:
      state.general.stack = try RegisterBytes.value(bytes, as: UInt32.self)
    case 5: state.general.ebp = try RegisterBytes.value(bytes, as: UInt32.self)
    case 6: state.general.esi = try RegisterBytes.value(bytes, as: UInt32.self)
    case 7: state.general.edi = try RegisterBytes.value(bytes, as: UInt32.self)
    case 8:
      state.general.program = try RegisterBytes.value(bytes, as: UInt32.self)
    case 9:
      state.general.flags = try RegisterBytes.value(bytes, as: UInt32.self)
    case 10:
      state.general.code = try RegisterBytes.value(bytes, as: UInt32.self)
    case 11:
      state.general.segment = try RegisterBytes.value(bytes, as: UInt32.self)
    case 12:
      state.general.data = try RegisterBytes.value(bytes, as: UInt32.self)
    case 13:
      state.general.extra = try RegisterBytes.value(bytes, as: UInt32.self)
    case 14:
      state.general.fs = try RegisterBytes.value(bytes, as: UInt32.self)
    case 15:
      state.general.gs = try RegisterBytes.value(bytes, as: UInt32.self)
    case 16 ... 23:
      let offset = Int(register.rawValue - 16) * 16
      try RegisterBytes.write(bytes, offset: offset, to: &state.floating.stack)
    case 24:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.control)
    case 25:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.status)
    case 26:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.tag)
    case 27:
      state.floating.code = try RegisterBytes.value(bytes, as: UInt32.self)
    case 28:
      state.floating.program = try RegisterBytes.value(bytes, as: UInt32.self)
    case 29:
      state.floating.segment = try RegisterBytes.value(bytes, as: UInt32.self)
    case 30:
      state.floating.data = try RegisterBytes.value(bytes, as: UInt32.self)
    case 31:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.opcode)
    case 32 ... 39:
      let offset = Int(register.rawValue - 32) * 16
      try RegisterBytes.write(bytes, offset: offset, to: &state.floating.vector)
    case 40:
      state.floating.mxcsr = try RegisterBytes.value(bytes, as: UInt32.self)
    default:
      throw .register
    }
  }
}
#endif
