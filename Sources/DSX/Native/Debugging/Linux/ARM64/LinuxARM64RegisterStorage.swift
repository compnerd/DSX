// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
internal struct LinuxGeneralRegisters: Sendable {
  internal var values: InlineArray<31, UInt64>
  internal var stack: UInt64
  internal var program: UInt64
  internal var status: UInt64

  internal init() {
    values = InlineArray<31, UInt64> { _ in 0 }
    stack = 0
    program = 0
    status = 0
  }
}

internal struct LinuxFloatingRegisters: Sendable {
  internal var values: InlineArray<64, UInt64>
  internal var status: UInt32
  internal var control: UInt32

  internal init() {
    values = InlineArray<64, UInt64> { _ in 0 }
    status = 0
    control = 0
  }
}

extension LinuxRegisters {
  internal static func read(_ state: borrowing LinuxRegisterState,
                            register: RegisterIdentifier,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 30:
      let value = state.general.values[Int(register.rawValue)]
      try RegisterBytes.append(value, size: 8, into: &output)
    case 31:
      try RegisterBytes.append(state.general.stack, size: 8, into: &output)
    case 32:
      try RegisterBytes.append(state.general.program, size: 8, into: &output)
    case 33:
      try RegisterBytes.append(state.general.status, size: 4, into: &output)
    case 34 ... 65:
      let offset = Int(register.rawValue - 34) * 16
      try RegisterBytes.append(state.floating.values, offset: offset, size: 16,
                               into: &output)
    case 66:
      try RegisterBytes.append(state.floating.status, size: 4, into: &output)
    case 67:
      try RegisterBytes.append(state.floating.control, size: 4, into: &output)
    case 68:
      try RegisterBytes.append(state.tls, size: 8, into: &output)
    default:
      throw .register
    }
  }

  internal static func write(_ state: inout LinuxRegisterState,
                             register: RegisterIdentifier,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 30:
      state.general.values[Int(register.rawValue)] =
          try RegisterBytes.value(bytes, as: UInt64.self)
    case 31:
      state.general.stack = try RegisterBytes.value(bytes, as: UInt64.self)
    case 32:
      state.general.program = try RegisterBytes.value(bytes, as: UInt64.self)
    case 33:
      let value = try RegisterBytes.value(bytes, as: UInt32.self)
      state.general.status = UInt64(value)
    case 34 ... 65:
      let offset = Int(register.rawValue - 34) * 16
      try RegisterBytes.write(bytes, offset: offset, to: &state.floating.values)
    case 66:
      state.floating.status = try RegisterBytes.value(bytes, as: UInt32.self)
    case 67:
      state.floating.control = try RegisterBytes.value(bytes, as: UInt32.self)
    case 68:
      state.tls = try RegisterBytes.value(bytes, as: UInt64.self)
    default:
      throw .register
    }
  }
}
#endif
