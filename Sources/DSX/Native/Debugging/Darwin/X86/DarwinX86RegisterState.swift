// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(x86_64)
internal import Darwin

private let kStackOffset =
    MemoryLayout<x86_float_state64_t>.offset(of: \.__fpu_stmm0)!
private let kStackStride =
    MemoryLayout<x86_float_state64_t>.offset(of: \.__fpu_stmm1)! - kStackOffset
private let kVectorOffset =
    MemoryLayout<x86_float_state64_t>.offset(of: \.__fpu_xmm0)!
private let kVectorStride =
    MemoryLayout<x86_float_state64_t>.offset(of: \.__fpu_xmm1)! - kVectorOffset

internal struct DarwinX86RegisterState: ~Copyable {
  private let thread: DarwinThread
  private var general: x86_thread_state64_t
  private var floating: x86_float_state64_t
}

extension DarwinX86RegisterState {
  internal static func synchronize(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    let thread = try DarwinThread(identifier)
    try thread.synchronize()
  }

  internal init(_ identifier: ProcessThreadIdentifier) throws(Debuggee.Error) {
    let thread = try DarwinThread(identifier)
    let general = try x86_thread_state64_t(thread.handle)
    var floating = x86_float_state64_t()
    try thread.handle.read(&floating, flavor: x86_FLOAT_STATE64)
    self.thread = consume thread
    self.general = general
    self.floating = floating
  }

  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let value: UInt64? = switch register.rawValue {
    case 0: general.__rax
    case 1: general.__rbx
    case 2: general.__rcx
    case 3: general.__rdx
    case 4: general.__rsi
    case 5: general.__rdi
    case 6: general.__rbp
    case 7: general.__rsp
    case 8: general.__r8
    case 9: general.__r9
    case 10: general.__r10
    case 11: general.__r11
    case 12: general.__r12
    case 13: general.__r13
    case 14: general.__r14
    case 15: general.__r15
    case 16: general.__rip
    case 17: general.__rflags
    case 18: general.__cs
    case 19 ... 21: 0
    case 22: general.__fs
    case 23: general.__gs
    default: nil
    }
    if let value {
      return try output.append(value, size: register.rawValue < 17 ? 8 : 4)
    }
    switch register.rawValue {
    case 24 ... 31:
      let offset = kStackOffset + Int(register.rawValue - 24) * kStackStride
      try output.append(floating, offset: offset, size: 10)
    case 32:
      try output.extend(floating.__fpu_fcw, size: 4)
    case 33:
      try output.extend(floating.__fpu_fsw, size: 4)
    case 34:
      try output.extend(floating.__fpu_ftw, size: 4)
    case 35:
      try output.extend(floating.__fpu_cs, size: 4)
    case 36:
      try output.append(floating.__fpu_ip, size: 4)
    case 37:
      try output.extend(floating.__fpu_ds, size: 4)
    case 38:
      try output.append(floating.__fpu_dp, size: 4)
    case 39:
      try output.extend(floating.__fpu_fop, size: 4)
    case 40 ... 55:
      let offset = kVectorOffset + Int(register.rawValue - 40) * kVectorStride
      try output.append(floating, offset: offset, size: 16)
    case 56:
      try output.append(floating.__fpu_mxcsr, size: 4)
    default:
      throw .register
    }
  }

  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0:
      general.__rax = try bytes.register(as: UInt64.self)
    case 1:
      general.__rbx = try bytes.register(as: UInt64.self)
    case 2:
      general.__rcx = try bytes.register(as: UInt64.self)
    case 3:
      general.__rdx = try bytes.register(as: UInt64.self)
    case 4:
      general.__rsi = try bytes.register(as: UInt64.self)
    case 5:
      general.__rdi = try bytes.register(as: UInt64.self)
    case 6:
      general.__rbp = try bytes.register(as: UInt64.self)
    case 7:
      general.__rsp = try bytes.register(as: UInt64.self)
    case 8:
      general.__r8 = try bytes.register(as: UInt64.self)
    case 9:
      general.__r9 = try bytes.register(as: UInt64.self)
    case 10:
      general.__r10 = try bytes.register(as: UInt64.self)
    case 11:
      general.__r11 = try bytes.register(as: UInt64.self)
    case 12:
      general.__r12 = try bytes.register(as: UInt64.self)
    case 13:
      general.__r13 = try bytes.register(as: UInt64.self)
    case 14:
      general.__r14 = try bytes.register(as: UInt64.self)
    case 15:
      general.__r15 = try bytes.register(as: UInt64.self)
    case 16:
      general.__rip = try bytes.register(as: UInt64.self)
    case 17:
      general.__rflags = try UInt64(bytes.register(as: UInt32.self))
    case 18:
      general.__cs = try UInt64(bytes.register(as: UInt32.self))
    case 19 ... 21:
      guard bytes.count == 4 else {
        throw .register
      }
    case 22:
      general.__fs = try UInt64(bytes.register(as: UInt32.self))
    case 23:
      general.__gs = try UInt64(bytes.register(as: UInt32.self))
    case 24 ... 31:
      guard bytes.count <= kStackStride else {
        throw .register
      }
      let offset = kStackOffset + Int(register.rawValue - 24) * kStackStride
      try bytes.write(offset: offset, to: &floating)
    case 32:
      try bytes.narrow(size: 4, to: &floating.__fpu_fcw)
    case 33:
      try bytes.narrow(size: 4, to: &floating.__fpu_fsw)
    case 34:
      try bytes.narrow(size: 4, to: &floating.__fpu_ftw)
    case 35:
      try bytes.narrow(size: 4, to: &floating.__fpu_cs)
    case 36:
      floating.__fpu_ip = try bytes.register(as: UInt32.self)
    case 37:
      try bytes.narrow(size: 4, to: &floating.__fpu_ds)
    case 38:
      floating.__fpu_dp = try bytes.register(as: UInt32.self)
    case 39:
      try bytes.narrow(size: 4, to: &floating.__fpu_fop)
    case 40 ... 55:
      guard bytes.count <= kVectorStride else {
        throw .register
      }
      let offset = kVectorOffset + Int(register.rawValue - 40) * kVectorStride
      try bytes.write(offset: offset, to: &floating)
    case 56:
      floating.__fpu_mxcsr = try bytes.register(as: UInt32.self)
    default:
      throw .register
    }
  }

  internal consuming func commit(_: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    try thread.handle.write(general, flavor: x86_THREAD_STATE64)
    try thread.handle.write(floating, flavor: x86_FLOAT_STATE64)
  }
}
#endif
