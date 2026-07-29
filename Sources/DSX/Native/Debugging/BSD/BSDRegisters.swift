// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(FreeBSD) || os(OpenBSD)) && arch(x86_64)
internal import Glibc

internal struct BSDRegisterState: Sendable {
  internal let thread: pid_t
  internal var general: InlineArray<192, UInt8>
  internal var floating: InlineArray<512, UInt8>

  internal init(thread: pid_t, general: InlineArray<192, UInt8>,
                floating: InlineArray<512, UInt8>) {
    self.thread = thread
    self.general = general
    self.floating = floating
  }
}

internal enum BSDRegisters {
  internal typealias State = BSDRegisterState

  internal static func synchronize(_: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
  }

  internal static func snapshot(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> BSDRegisterState {
    let thread = try identifier.native
    var general = InlineArray<192, UInt8> { _ in 0 }
    try transfer(PT_GETREGS, thread: thread, value: &general)
    var floating = InlineArray<512, UInt8> { _ in 0 }
    try transfer(PT_GETFPREGS, thread: thread, value: &floating)
    return BSDRegisterState(thread: thread, general: general,
                            floating: floating)
  }

  internal static func read(_ state: borrowing BSDRegisterState,
                            register: RegisterIdentifier,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 23:
      let location = try location(register)
      if location.native == location.size {
        try RegisterBytes.append(state.general, offset: location.offset,
                                 size: location.size, into: &output)
      } else {
        try RegisterBytes.extend(state.general, offset: location.offset,
                                 native: location.native, size: location.size,
                                 into: &output)
      }
    case 24 ... 31:
      let offset = 32 + Int(register.rawValue - 24) * 16
      try RegisterBytes.append(state.floating, offset: offset, size: 10,
                               into: &output)
    case 32:
      try RegisterBytes.extend(state.floating, offset: 0, native: 2, size: 4,
                               into: &output)
    case 33:
      try RegisterBytes.extend(state.floating, offset: 2, native: 2, size: 4,
                               into: &output)
    case 34:
      try RegisterBytes.extend(state.floating, offset: 4, native: 1, size: 4,
                               into: &output)
    case 35, 37:
      try RegisterBytes.append(UInt32(0), size: 4, into: &output)
    case 36:
      try RegisterBytes.append(state.floating, offset: 8, size: 4,
                               into: &output)
    case 38:
      try RegisterBytes.append(state.floating, offset: 16, size: 4,
                               into: &output)
    case 39:
      try RegisterBytes.extend(state.floating, offset: 6, native: 2, size: 4,
                               into: &output)
    case 40 ... 55:
      let offset = 160 + Int(register.rawValue - 40) * 16
      try RegisterBytes.append(state.floating, offset: offset, size: 16,
                               into: &output)
    case 56:
      try RegisterBytes.append(state.floating, offset: 24, size: 4,
                               into: &output)
    default:
      throw .register
    }
  }

  internal static func write(_ state: inout BSDRegisterState,
                             register: RegisterIdentifier,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 23:
      let location = try location(register)
      if location.native == location.size {
        try RegisterBytes.write(bytes, offset: location.offset,
                                to: &state.general)
      } else {
        try RegisterBytes.narrow(bytes, offset: location.offset,
                                 native: location.native, size: location.size,
                                 to: &state.general)
      }
    case 24 ... 31:
      let offset = 32 + Int(register.rawValue - 24) * 16
      try RegisterBytes.write(bytes, offset: offset, to: &state.floating)
    case 32:
      try RegisterBytes.narrow(bytes, offset: 0, native: 2, size: 4,
                               to: &state.floating)
    case 33:
      try RegisterBytes.narrow(bytes, offset: 2, native: 2, size: 4,
                               to: &state.floating)
    case 34:
      try RegisterBytes.narrow(bytes, offset: 4, native: 1, size: 4,
                               to: &state.floating)
    case 35, 37:
      guard bytes.count == 4 else {
        throw .register
      }
    case 36:
      try RegisterBytes.write(bytes, offset: 8, to: &state.floating)
    case 38:
      try RegisterBytes.write(bytes, offset: 16, to: &state.floating)
    case 39:
      try RegisterBytes.narrow(bytes, offset: 6, native: 2, size: 4,
                               to: &state.floating)
    case 40 ... 55:
      let offset = 160 + Int(register.rawValue - 40) * 16
      try RegisterBytes.write(bytes, offset: offset, to: &state.floating)
    case 56:
      try RegisterBytes.write(bytes, offset: 24, to: &state.floating)
    default:
      throw .register
    }
  }

  internal static func commit(_ state: consuming BSDRegisterState,
                              thread identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    var state = consume state
    guard try state.thread == identifier.native else {
      throw .thread
    }
    try transfer(PT_SETREGS, thread: state.thread, value: &state.general)
    try transfer(PT_SETFPREGS, thread: state.thread, value: &state.floating)
  }

  private static func location(_ register: RegisterIdentifier)
      throws(Debuggee.Error) -> BSDRegisterLocation {
#if os(FreeBSD)
    return switch register.rawValue {
    case 0: BSDRegisterLocation(offset: 112, native: 8, size: 8)
    case 1: BSDRegisterLocation(offset: 88, native: 8, size: 8)
    case 2: BSDRegisterLocation(offset: 104, native: 8, size: 8)
    case 3: BSDRegisterLocation(offset: 96, native: 8, size: 8)
    case 4: BSDRegisterLocation(offset: 72, native: 8, size: 8)
    case 5: BSDRegisterLocation(offset: 64, native: 8, size: 8)
    case 6: BSDRegisterLocation(offset: 80, native: 8, size: 8)
    case 7: BSDRegisterLocation(offset: 160, native: 8, size: 8)
    case 8: BSDRegisterLocation(offset: 56, native: 8, size: 8)
    case 9: BSDRegisterLocation(offset: 48, native: 8, size: 8)
    case 10: BSDRegisterLocation(offset: 40, native: 8, size: 8)
    case 11: BSDRegisterLocation(offset: 32, native: 8, size: 8)
    case 12: BSDRegisterLocation(offset: 24, native: 8, size: 8)
    case 13: BSDRegisterLocation(offset: 16, native: 8, size: 8)
    case 14: BSDRegisterLocation(offset: 8, native: 8, size: 8)
    case 15: BSDRegisterLocation(offset: 0, native: 8, size: 8)
    case 16: BSDRegisterLocation(offset: 136, native: 8, size: 8)
    case 17: BSDRegisterLocation(offset: 152, native: 4, size: 4)
    case 18: BSDRegisterLocation(offset: 144, native: 4, size: 4)
    case 19: BSDRegisterLocation(offset: 168, native: 4, size: 4)
    case 20: BSDRegisterLocation(offset: 134, native: 2, size: 4)
    case 21: BSDRegisterLocation(offset: 132, native: 2, size: 4)
    case 22: BSDRegisterLocation(offset: 124, native: 2, size: 4)
    case 23: BSDRegisterLocation(offset: 126, native: 2, size: 4)
    default: throw .register
    }
#else
    let offset: Int = switch register.rawValue {
    case 0: 112
    case 1: 104
    case 2: 24
    case 3: 16
    case 4: 8
    case 5: 0
    case 6: 96
    case 7: 120
    case 8: 32
    case 9: 40
    case 10: 48
    case 11: 56
    case 12: 64
    case 13: 72
    case 14: 80
    case 15: 88
    case 16: 128
    case 17: 136
    case 18: 144
    case 19: 152
    case 20: 160
    case 21: 168
    case 22: 176
    case 23: 184
    default: throw .register
    }
    let size = register.rawValue < 17 ? 8 : 4
    let native = register.rawValue < 17 ? 8 : 4
    return BSDRegisterLocation(offset: offset, native: native, size: size)
#endif
  }

  private static func transfer<Value>(_ request: CInt, thread: pid_t,
                                      value: inout Value)
      throws(Debuggee.Error) {
    let result = withUnsafeMutablePointer(to: &value) { value in
      let pointer = UnsafeMutableRawPointer(value)
        .assumingMemoryBound(to: CChar.self)
      ptrace(request, thread, pointer, 0)
    }
    guard result == 0 else {
      throw failure(errno)
    }
  }

  private static func failure(_ code: CInt) -> Debuggee.Error {
    switch code {
    case EINVAL: .unsupported
    default: UnixError.debuggee(code, invalid: .thread, support: true)
    }
  }
}

private struct BSDRegisterLocation {
  fileprivate let offset: Int
  fileprivate let native: Int
  fileprivate let size: Int
}
#endif
