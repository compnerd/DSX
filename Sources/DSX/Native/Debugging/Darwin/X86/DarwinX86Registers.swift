// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(x86_64)
internal import Darwin

internal struct DarwinX86RegisterState: ~Copyable {
  fileprivate let thread: thread_act_t
  fileprivate var general: x86_thread_state64_t
  fileprivate var floating: x86_float_state64_t

  fileprivate init(thread: thread_act_t, general: x86_thread_state64_t,
                   floating: x86_float_state64_t) {
    self.thread = thread
    self.general = general
    self.floating = floating
  }

  deinit {
    _ = mach_port_deallocate(mach_task_self_, thread)
  }
}

internal enum DarwinX86Registers {
  internal typealias State = DarwinX86RegisterState

  internal static func synchronize(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    let thread = try thread(identifier)
    let status = thread_abort_safely(thread)
    _ = mach_port_deallocate(mach_task_self_, thread)
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
  }

  internal static func snapshot(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> DarwinX86RegisterState {
    let thread = try thread(identifier)
    do throws(Debuggee.Error) {
      var general = x86_thread_state64_t()
      try fetch(thread, flavor: x86_THREAD_STATE64, value: &general)
      var floating = x86_float_state64_t()
      try fetch(thread, flavor: x86_FLOAT_STATE64, value: &floating)
      return DarwinX86RegisterState(thread: thread, general: general,
                                    floating: floating)
    } catch {
      _ = mach_port_deallocate(mach_task_self_, thread)
      throw error
    }
  }

  internal static func read(_ state: borrowing DarwinX86RegisterState,
                            register: RegisterIdentifier,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let value: UInt64? = switch register.rawValue {
    case 0: state.general.__rax
    case 1: state.general.__rbx
    case 2: state.general.__rcx
    case 3: state.general.__rdx
    case 4: state.general.__rsi
    case 5: state.general.__rdi
    case 6: state.general.__rbp
    case 7: state.general.__rsp
    case 8: state.general.__r8
    case 9: state.general.__r9
    case 10: state.general.__r10
    case 11: state.general.__r11
    case 12: state.general.__r12
    case 13: state.general.__r13
    case 14: state.general.__r14
    case 15: state.general.__r15
    case 16: state.general.__rip
    case 17: state.general.__rflags
    case 18: state.general.__cs
    case 19 ... 21: 0
    case 22: state.general.__fs
    case 23: state.general.__gs
    default: nil
    }
    if let value {
      return try RegisterBytes.append(value,
                                      size: register.rawValue < 17 ? 8 : 4,
                                      into: &output)
    }
    switch register.rawValue {
    case 24 ... 31:
      try stack(state, index: Int(register.rawValue - 24), into: &output)
    case 32:
      try RegisterBytes.extend(state.floating.__fpu_fcw, size: 4, into: &output)
    case 33:
      try RegisterBytes.extend(state.floating.__fpu_fsw, size: 4, into: &output)
    case 34:
      try RegisterBytes.extend(state.floating.__fpu_ftw, size: 4, into: &output)
    case 35:
      try RegisterBytes.extend(state.floating.__fpu_cs, size: 4, into: &output)
    case 36:
      try RegisterBytes.append(state.floating.__fpu_ip, size: 4, into: &output)
    case 37:
      try RegisterBytes.extend(state.floating.__fpu_ds, size: 4, into: &output)
    case 38:
      try RegisterBytes.append(state.floating.__fpu_dp, size: 4, into: &output)
    case 39:
      try RegisterBytes.extend(state.floating.__fpu_fop, size: 4, into: &output)
    case 40 ... 55:
      try vector(state, index: Int(register.rawValue - 40), into: &output)
    case 56:
      try RegisterBytes.append(state.floating.__fpu_mxcsr, size: 4,
                               into: &output)
    default:
      throw .register
    }
  }

  internal static func write(_ state: inout DarwinX86RegisterState,
                             register: RegisterIdentifier,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0:
      state.general.__rax = try RegisterBytes.value(bytes, as: UInt64.self)
    case 1:
      state.general.__rbx = try RegisterBytes.value(bytes, as: UInt64.self)
    case 2:
      state.general.__rcx = try RegisterBytes.value(bytes, as: UInt64.self)
    case 3:
      state.general.__rdx = try RegisterBytes.value(bytes, as: UInt64.self)
    case 4:
      state.general.__rsi = try RegisterBytes.value(bytes, as: UInt64.self)
    case 5:
      state.general.__rdi = try RegisterBytes.value(bytes, as: UInt64.self)
    case 6:
      state.general.__rbp = try RegisterBytes.value(bytes, as: UInt64.self)
    case 7:
      state.general.__rsp = try RegisterBytes.value(bytes, as: UInt64.self)
    case 8:
      state.general.__r8 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 9:
      state.general.__r9 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 10:
      state.general.__r10 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 11:
      state.general.__r11 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 12:
      state.general.__r12 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 13:
      state.general.__r13 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 14:
      state.general.__r14 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 15:
      state.general.__r15 = try RegisterBytes.value(bytes, as: UInt64.self)
    case 16:
      state.general.__rip = try RegisterBytes.value(bytes, as: UInt64.self)
    case 17:
      state.general.__rflags =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 18:
      state.general.__cs =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 19 ... 21:
      guard bytes.count == 4 else {
        throw .register
      }
    case 22:
      state.general.__fs =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 23:
      state.general.__gs =
          try UInt64(RegisterBytes.value(bytes, as: UInt32.self))
    case 24 ... 31:
      try stack(&state, index: Int(register.rawValue - 24), bytes: bytes)
    case 32:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.__fpu_fcw)
    case 33:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.__fpu_fsw)
    case 34:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.__fpu_ftw)
    case 35:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.__fpu_cs)
    case 36:
      state.floating.__fpu_ip = try RegisterBytes.value(bytes, as: UInt32.self)
    case 37:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.__fpu_ds)
    case 38:
      state.floating.__fpu_dp = try RegisterBytes.value(bytes, as: UInt32.self)
    case 39:
      try RegisterBytes.narrow(bytes, size: 4, to: &state.floating.__fpu_fop)
    case 40 ... 55:
      try vector(&state, index: Int(register.rawValue - 40), bytes: bytes)
    case 56:
      state.floating.__fpu_mxcsr =
          try RegisterBytes.value(bytes, as: UInt32.self)
    default:
      throw .register
    }
  }

  internal static func commit(_ state: consuming DarwinX86RegisterState,
                              thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    var state = consume state
    try store(state.thread, flavor: x86_THREAD_STATE64, value: &state.general)
    try store(state.thread, flavor: x86_FLOAT_STATE64, value: &state.floating)
  }

  private static func fetch<Value>(_ thread: thread_act_t, flavor: Int32,
                                   value: inout Value) throws(Debuggee.Error) {
    let bytes = MemoryLayout<Value>.size
    let words = bytes / MemoryLayout<natural_t>.size
    var count = mach_msg_type_number_t(words)
    let status = withUnsafeMutablePointer(to: &value) { value in
      value.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_get_state(thread, thread_state_flavor_t(flavor), $0, &count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
  }

  private static func store<Value>(_ thread: thread_act_t, flavor: Int32,
                                   value: inout Value) throws(Debuggee.Error) {
    let bytes = MemoryLayout<Value>.size
    let words = bytes / MemoryLayout<natural_t>.size
    let count = mach_msg_type_number_t(words)
    let status = withUnsafeMutablePointer(to: &value) { value in
      value.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_set_state(thread, thread_state_flavor_t(flavor), $0, count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
  }

  private static func thread(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) -> thread_act_t {
    var list = try DarwinThreadList(identifier.process)
    return try list.take(identifier.thread)
  }

  private static func stack(_ state: borrowing DarwinX86RegisterState,
                            index: Int, into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch index {
    case 0:
      try RegisterBytes.append(state.floating.__fpu_stmm0, size: 10,
                               into: &output)
    case 1:
      try RegisterBytes.append(state.floating.__fpu_stmm1, size: 10,
                               into: &output)
    case 2:
      try RegisterBytes.append(state.floating.__fpu_stmm2, size: 10,
                               into: &output)
    case 3:
      try RegisterBytes.append(state.floating.__fpu_stmm3, size: 10,
                               into: &output)
    case 4:
      try RegisterBytes.append(state.floating.__fpu_stmm4, size: 10,
                               into: &output)
    case 5:
      try RegisterBytes.append(state.floating.__fpu_stmm5, size: 10,
                               into: &output)
    case 6:
      try RegisterBytes.append(state.floating.__fpu_stmm6, size: 10,
                               into: &output)
    case 7:
      try RegisterBytes.append(state.floating.__fpu_stmm7, size: 10,
                               into: &output)
    default:
      throw .register
    }
  }

  private static func stack(_ state: inout DarwinX86RegisterState, index: Int,
                            bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch index {
    case 0: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_stmm0)
    case 1: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_stmm1)
    case 2: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_stmm2)
    case 3: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_stmm3)
    case 4: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_stmm4)
    case 5: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_stmm5)
    case 6: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_stmm6)
    case 7: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_stmm7)
    default: throw .register
    }
  }

  private static func vector(_ state: borrowing DarwinX86RegisterState,
                             index: Int, into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch index {
    case 0: try RegisterBytes.append(state.floating.__fpu_xmm0, size: 16,
                                     into: &output)
    case 1: try RegisterBytes.append(state.floating.__fpu_xmm1, size: 16,
                                     into: &output)
    case 2: try RegisterBytes.append(state.floating.__fpu_xmm2, size: 16,
                                     into: &output)
    case 3: try RegisterBytes.append(state.floating.__fpu_xmm3, size: 16,
                                     into: &output)
    case 4: try RegisterBytes.append(state.floating.__fpu_xmm4, size: 16,
                                     into: &output)
    case 5: try RegisterBytes.append(state.floating.__fpu_xmm5, size: 16,
                                     into: &output)
    case 6: try RegisterBytes.append(state.floating.__fpu_xmm6, size: 16,
                                     into: &output)
    case 7: try RegisterBytes.append(state.floating.__fpu_xmm7, size: 16,
                                     into: &output)
    case 8: try RegisterBytes.append(state.floating.__fpu_xmm8, size: 16,
                                     into: &output)
    case 9: try RegisterBytes.append(state.floating.__fpu_xmm9, size: 16,
                                     into: &output)
    case 10: try RegisterBytes.append(state.floating.__fpu_xmm10, size: 16,
                                      into: &output)
    case 11: try RegisterBytes.append(state.floating.__fpu_xmm11, size: 16,
                                      into: &output)
    case 12: try RegisterBytes.append(state.floating.__fpu_xmm12, size: 16,
                                      into: &output)
    case 13: try RegisterBytes.append(state.floating.__fpu_xmm13, size: 16,
                                      into: &output)
    case 14: try RegisterBytes.append(state.floating.__fpu_xmm14, size: 16,
                                      into: &output)
    case 15: try RegisterBytes.append(state.floating.__fpu_xmm15, size: 16,
                                      into: &output)
    default: throw .register
    }
  }

  private static func vector(_ state: inout DarwinX86RegisterState, index: Int,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch index {
    case 0: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm0)
    case 1: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm1)
    case 2: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm2)
    case 3: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm3)
    case 4: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm4)
    case 5: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm5)
    case 6: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm6)
    case 7: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm7)
    case 8: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm8)
    case 9: try RegisterBytes.write(bytes, offset: 0,
                                    to: &state.floating.__fpu_xmm9)
    case 10: try RegisterBytes.write(bytes, offset: 0,
                                     to: &state.floating.__fpu_xmm10)
    case 11: try RegisterBytes.write(bytes, offset: 0,
                                     to: &state.floating.__fpu_xmm11)
    case 12: try RegisterBytes.write(bytes, offset: 0,
                                     to: &state.floating.__fpu_xmm12)
    case 13: try RegisterBytes.write(bytes, offset: 0,
                                     to: &state.floating.__fpu_xmm13)
    case 14: try RegisterBytes.write(bytes, offset: 0,
                                     to: &state.floating.__fpu_xmm14)
    case 15: try RegisterBytes.write(bytes, offset: 0,
                                     to: &state.floating.__fpu_xmm15)
    default: throw .register
    }
  }

}
#endif
