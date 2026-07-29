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

extension LinuxRegisterState {
  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    if let scalable, (34 ... 67).contains(register.rawValue) ||
        (167 ... 216).contains(register.rawValue) {
      return try scalable.read(register.rawValue, into: &output)
    }
    switch register.rawValue {
    case 0 ... 30:
      let value = general.values[Int(register.rawValue)]
      try output.append(value, size: 8)
    case 31:
      try output.append(general.stack, size: 8)
    case 32:
      try output.append(general.program, size: 8)
    case 33:
      try output.append(general.status, size: 4)
    case 34 ... 65:
      let offset = Int(register.rawValue - 34) * 16
      try output.append(floating.values, offset: offset, size: 16)
    case 66:
      try output.append(floating.status, size: 4)
    case 67:
      try output.append(floating.control, size: 4)
    case 68:
      try output.append(tls, size: 8)
    case 165 ... 166:
      guard let masks else {
        throw .register
      }
      try output.append(masks[Int(register.rawValue - 165)], size: 8)
    default:
      throw .register
    }
  }

  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    if scalable != nil, (34 ... 67).contains(register.rawValue) ||
        (167 ... 216).contains(register.rawValue) {
      try scalable?.write(register.rawValue, bytes: bytes)
      return
    }
    switch register.rawValue {
    case 0 ... 30:
      general.values[Int(register.rawValue)] =
          try bytes.register(as: UInt64.self)
    case 31:
      general.stack = try bytes.register(as: UInt64.self)
    case 32:
      general.program = try bytes.register(as: UInt64.self)
    case 33:
      let value = try bytes.register(as: UInt32.self)
      general.status = UInt64(value)
    case 34 ... 65:
      let offset = Int(register.rawValue - 34) * 16
      try bytes.write(offset: offset, to: &floating.values)
    case 66:
      floating.status = try bytes.register(as: UInt32.self)
    case 67:
      floating.control = try bytes.register(as: UInt32.self)
    case 68:
      tls = try bytes.register(as: UInt64.self)
    case 165 ... 166:
      guard let masks else {
        throw .register
      }
      let value = try bytes.register(as: UInt64.self)
      guard value == masks[Int(register.rawValue - 165)] else {
        throw .register
      }
    default:
      throw .register
    }
  }
}
#endif
