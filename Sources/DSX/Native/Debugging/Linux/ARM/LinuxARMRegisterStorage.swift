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

extension LinuxRegisterState {
  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 15:
      let value = general.values[Int(register.rawValue)]
      try output.append(value, size: 4)
    case 16:
      try output.append(general.values[16], size: 4)
    case 17 ... 48:
      let value = floating.values[Int(register.rawValue - 17)]
      try output.append(value, size: 8)
    case 49:
      try output.append(floating.status, size: 4)
    default:
      throw .register
    }
  }

  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 15:
      general.values[Int(register.rawValue)] =
          try bytes.register(as: UInt32.self)
    case 16:
      general.values[16] = try bytes.register(as: UInt32.self)
    case 17 ... 48:
      floating.values[Int(register.rawValue - 17)] =
          try bytes.register(as: UInt64.self)
    case 49:
      floating.status = try bytes.register(as: UInt32.self)
    default:
      throw .register
    }
  }
}
#endif
