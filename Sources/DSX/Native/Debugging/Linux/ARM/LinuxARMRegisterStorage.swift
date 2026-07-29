// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm)
internal struct LinuxGeneralRegisters: Sendable {
  internal var values: InlineArray<18, UInt32>

  internal init() {
    values = InlineArray<18, UInt32> { _ in 0 }
  }
}

internal struct LinuxFloatingRegisters: Sendable {
  internal var values: InlineArray<32, UInt64>
  internal var status: UInt32

  internal init() {
    values = InlineArray<32, UInt64> { _ in 0 }
    status = 0
  }
}

extension LinuxRegisters {
  internal static func read(_ state: borrowing LinuxRegisterState,
                            register: RegisterIdentifier,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 15:
      let value = state.general.values[Int(register.rawValue)]
      try RegisterBytes.append(value, size: 4, into: &output)
    case 16:
      try RegisterBytes.append(state.general.values[16], size: 4, into: &output)
    case 17 ... 48:
      let value = state.floating.values[Int(register.rawValue - 17)]
      try RegisterBytes.append(value, size: 8, into: &output)
    case 49:
      try RegisterBytes.append(state.floating.status, size: 4, into: &output)
    default:
      throw .register
    }
  }

  internal static func write(_ state: inout LinuxRegisterState,
                             register: RegisterIdentifier,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 15:
      state.general.values[Int(register.rawValue)] =
          try RegisterBytes.value(bytes, as: UInt32.self)
    case 16:
      state.general.values[16] = try RegisterBytes.value(bytes, as: UInt32.self)
    case 17 ... 48:
      state.floating.values[Int(register.rawValue - 17)] =
          try RegisterBytes.value(bytes, as: UInt64.self)
    case 49:
      state.floating.status = try RegisterBytes.value(bytes, as: UInt32.self)
    default:
      throw .register
    }
  }
}
#endif
