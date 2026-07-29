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
private let kUpperOffset =
    MemoryLayout<x86_avx_state64_t>.offset(of: \.__fpu_ymmh0)!

internal struct DarwinX86RegisterState: ~Copyable {
  private let thread: DarwinThread
  private var general: x86_thread_state64_t
  private var floating: x86_float_state64_t
  private let exception: x86_exception_state64_t
  private var extended: x86_avx_state64_t?

  internal var configuration: RegisterConfiguration {
    RegisterConfiguration(vector: extended != nil)
  }

  private static var vector: Bool {
    var value: CInt = 0
    var size = MemoryLayout<CInt>.size
    return sysctlbyname("hw.optional.avx1_0", &value, &size, nil, 0) == 0 &&
        value != 0
  }
}

extension DarwinX86RegisterState {
  internal static func access(_ register: RegisterIdentifier)
      -> RegisterAccess {
    switch register.rawValue {
    case 19 ... 21: .unavailable
    case 75 ... 77: .immutable
    default: .mutable
    }
  }

  internal static func synchronize(_ identifier: ProcessThreadIdentifier,
                                   control: borrowing NativeDebugControl =
                                       NativeDebugControl())
      throws(Debuggee.Error) {
    let thread = try DarwinThread(identifier, control: control)
    try thread.synchronize()
  }

  internal init(_ identifier: ProcessThreadIdentifier,
                control: borrowing NativeDebugControl = NativeDebugControl())
      throws(Debuggee.Error) {
    let thread = try DarwinThread(identifier, control: control)
    let general = try x86_thread_state64_t(thread.handle)
    var floating = x86_float_state64_t()
    try thread.handle.read(&floating, flavor: x86_FLOAT_STATE64)
    var exception = x86_exception_state64_t()
    try thread.handle.read(&exception, flavor: x86_EXCEPTION_STATE64)
    var extended: x86_avx_state64_t?
    if DarwinX86RegisterState.vector {
      var state = x86_avx_state64_t()
      try thread.handle.read(&state, flavor: x86_AVX_STATE64)
      extended = state
    }
    self.thread = consume thread
    self.general = general
    self.floating = floating
    self.exception = exception
    self.extended = extended
  }

  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    if let index = register.ymm {
      guard let extended else {
        throw .register
      }
      return try output.append(extended, offset: kUpperOffset + index * 16,
                               size: 16)
    }
    if let value = general.value(register) {
      return try output.append(value, size: register.rawValue < 17 ? 8 : 4)
    }
    switch register.rawValue {
    case 75:
      try output.append(exception.__trapno, size: 2)
    case 76:
      try output.append(exception.__err, size: 4)
    case 77:
      try output.append(exception.__faultvaddr, size: 8)
    default:
      try floating.read(register, into: &output)
    }
  }
}

extension x86_thread_state64_t {
  fileprivate func value(_ register: RegisterIdentifier) -> UInt64? {
    switch register.rawValue {
    case 0: __rax
    case 1: __rbx
    case 2: __rcx
    case 3: __rdx
    case 4: __rsi
    case 5: __rdi
    case 6: __rbp
    case 7: __rsp
    case 8: __r8
    case 9: __r9
    case 10: __r10
    case 11: __r11
    case 12: __r12
    case 13: __r13
    case 14: __r14
    case 15: __r15
    case 16: __rip
    case 17: __rflags
    case 18: __cs
    case 22: __fs
    case 23: __gs
    default: nil
    }
  }
}

extension x86_float_state64_t {
  fileprivate func read(_ register: RegisterIdentifier,
                        into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 24 ... 31:
      let offset = kStackOffset + Int(register.rawValue - 24) * kStackStride
      try output.append(self, offset: offset, size: 10)
    case 32:
      try output.extend(__fpu_fcw, size: 4)
    case 33:
      try output.extend(__fpu_fsw, size: 4)
    case 34:
      try output.extend(__fpu_ftw, size: 4)
    case 35:
      try output.extend(__fpu_cs, size: 4)
    case 36:
      try output.append(__fpu_ip, size: 4)
    case 37:
      try output.extend(__fpu_ds, size: 4)
    case 38:
      try output.append(__fpu_dp, size: 4)
    case 39:
      try output.extend(__fpu_fop, size: 4)
    case 40 ... 55:
      let offset = kVectorOffset + Int(register.rawValue - 40) * kVectorStride
      try output.append(self, offset: offset, size: 16)
    case 56:
      try output.append(__fpu_mxcsr, size: 4)
    default:
      throw .register
    }
  }
}

extension DarwinX86RegisterState {
  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    if let index = register.ymm {
      guard extended != nil, bytes.count == 16 else {
        throw .register
      }
      return try bytes.write(offset: kUpperOffset + index * 16, to: &extended!)
    }
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

  internal consuming func commit() throws(Debuggee.Error) {
    try thread.handle.write(general, flavor: x86_THREAD_STATE64)
    // Exception registers describe the kernel's last fault, not execution
    // state. XNU rejects x86_EXCEPTION_STATE64 in thread_set_state.
    if var extended {
      withUnsafeBytes(of: floating) { source in
        withUnsafeMutableBytes(of: &extended) { target in
          target.copyMemory(from: source)
        }
      }
      return try thread.handle.write(extended, flavor: x86_AVX_STATE64)
    }
    try thread.handle.write(floating, flavor: x86_FLOAT_STATE64)
  }
}
#endif
