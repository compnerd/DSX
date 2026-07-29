// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(arm64)
internal import Darwin

internal struct DarwinARM64RegisterState: ~Copyable {
  fileprivate let thread: thread_act_t
  fileprivate var general: arm_thread_state64_t
  fileprivate var vector: arm_neon_state64_t
  fileprivate var exception: arm_exception_state64_t

  fileprivate init(thread: thread_act_t, general: arm_thread_state64_t,
                   vector: arm_neon_state64_t,
                   exception: arm_exception_state64_t) {
    self.thread = thread
    self.general = general
    self.vector = vector
    self.exception = exception
  }

  deinit {
    _ = mach_port_deallocate(mach_task_self_, thread)
  }
}

internal enum DarwinARM64Registers {
  internal typealias State = DarwinARM64RegisterState

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
      throws(Debuggee.Error) -> DarwinARM64RegisterState {
    let thread = try thread(identifier)
    do throws(Debuggee.Error) {
      var general = arm_thread_state64_t()
      let bytes = MemoryLayout<arm_thread_state64_t>.size
      var words = bytes / MemoryLayout<UInt32>.size
      var count = mach_msg_type_number_t(words)
      var status = withUnsafeMutablePointer(to: &general) { state in
        state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
          thread_get_state(thread, thread_state_flavor_t(ARM_THREAD_STATE64),
                           $0, &count)
        }
      }
      guard status == KERN_SUCCESS else {
        throw DarwinError.debuggee(status, invalid: .thread)
      }
      var vector = arm_neon_state64_t()
      words = MemoryLayout<arm_neon_state64_t>.size / MemoryLayout<UInt32>.size
      count = mach_msg_type_number_t(words)
      status = withUnsafeMutablePointer(to: &vector) { state in
        state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
          thread_get_state(thread, thread_state_flavor_t(ARM_NEON_STATE64), $0,
                           &count)
        }
      }
      guard status == KERN_SUCCESS else {
        throw DarwinError.debuggee(status, invalid: .thread)
      }
      var exception = arm_exception_state64_t()
      let size = MemoryLayout<arm_exception_state64_t>.size
      words = size / MemoryLayout<UInt32>.size
      count = mach_msg_type_number_t(words)
      status = withUnsafeMutablePointer(to: &exception) { state in
        state.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
          thread_get_state(thread, thread_state_flavor_t(ARM_EXCEPTION_STATE64),
                           $0, &count)
        }
      }
      guard status == KERN_SUCCESS else {
        throw DarwinError.debuggee(status, invalid: .thread)
      }
      return DarwinARM64RegisterState(thread: thread, general: general,
                                      vector: vector, exception: exception)
    } catch {
      _ = mach_port_deallocate(mach_task_self_, thread)
      throw error
    }
  }

  internal static func read(_ state: borrowing DarwinARM64RegisterState,
                            register: RegisterIdentifier,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 28:
      try append(general(state, index: Int(register.rawValue)), size: 8,
                 into: &output)
    case 29:
      try append(state.general.__fp, size: 8, into: &output)
    case 30:
      try append(state.general.__lr, size: 8, into: &output)
    case 31:
      try append(state.general.__sp, size: 8, into: &output)
    case 32:
      try append(state.general.__pc, size: 8, into: &output)
    case 33:
      try append(UInt64(state.general.__cpsr), size: 4, into: &output)
    case 34 ... 65:
      try vector(state, index: Int(register.rawValue - 34), into: &output)
    case 66:
      try append(UInt64(state.vector.__fpsr), size: 4, into: &output)
    case 67:
      try append(UInt64(state.vector.__fpcr), size: 4, into: &output)
    case 162:
      try append(state.exception.__far, size: 8, into: &output)
    case 163:
      try append(UInt64(state.exception.__esr), size: 4, into: &output)
    case 164:
      try append(UInt64(state.exception.__exception), size: 4, into: &output)
    default:
      throw .register
    }
  }

  internal static func write(_ state: inout DarwinARM64RegisterState,
                             register: RegisterIdentifier,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 28:
      try general(&state, index: Int(register.rawValue),
                  value: value(bytes, size: 8))
    case 29:
      state.general.__fp = try value(bytes, size: 8)
    case 30:
      state.general.__lr = try value(bytes, size: 8)
    case 31:
      state.general.__sp = try value(bytes, size: 8)
    case 32:
      state.general.__pc = try value(bytes, size: 8)
    case 33:
      state.general.__cpsr = try UInt32(value(bytes, size: 4))
    case 34 ... 65:
      try vector(&state, index: Int(register.rawValue - 34), bytes: bytes)
    case 66:
      state.vector.__fpsr = try UInt32(value(bytes, size: 4))
    case 67:
      state.vector.__fpcr = try UInt32(value(bytes, size: 4))
    case 162:
      state.exception.__far = try value(bytes, size: 8)
    case 163:
      state.exception.__esr = try UInt32(value(bytes, size: 4))
    case 164:
      state.exception.__exception = try UInt32(value(bytes, size: 4))
    default:
      throw .register
    }
  }

  internal static func commit(_ state: consuming DarwinARM64RegisterState,
                              thread: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    var state = consume state
    let bytes = MemoryLayout<arm_thread_state64_t>.size
    var words = bytes / MemoryLayout<UInt32>.size
    var count = mach_msg_type_number_t(words)
    var status = withUnsafeMutablePointer(to: &state.general) { value in
      value.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_set_state(state.thread,
                         thread_state_flavor_t(ARM_THREAD_STATE64), $0, count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    words = MemoryLayout<arm_neon_state64_t>.size / MemoryLayout<UInt32>.size
    count = mach_msg_type_number_t(words)
    status = withUnsafeMutablePointer(to: &state.vector) { value in
      value.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_set_state(state.thread, thread_state_flavor_t(ARM_NEON_STATE64),
                         $0, count)
      }
    }
    guard status == KERN_SUCCESS else {
      throw DarwinError.debuggee(status, invalid: .thread)
    }
    let size = MemoryLayout<arm_exception_state64_t>.size
    words = size / MemoryLayout<UInt32>.size
    count = mach_msg_type_number_t(words)
    status = withUnsafeMutablePointer(to: &state.exception) { value in
      value.withMemoryRebound(to: natural_t.self, capacity: Int(count)) {
        thread_set_state(state.thread,
                         thread_state_flavor_t(ARM_EXCEPTION_STATE64), $0,
                         count)
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

  private static func general(_ state: borrowing DarwinARM64RegisterState,
                              index: Int) -> UInt64 {
    withUnsafeBytes(of: state.general.__x) { bytes in
      bytes.loadUnaligned(fromByteOffset: index * 8, as: UInt64.self)
    }
  }

  private static func general(_ state: inout DarwinARM64RegisterState,
                              index: Int, value: UInt64)
      throws(Debuggee.Error) {
    withUnsafeMutableBytes(of: &state.general.__x) { bytes in
      bytes.storeBytes(of: value, toByteOffset: index * 8, as: UInt64.self)
    }
  }

  private static func vector(_ state: borrowing DarwinARM64RegisterState,
                             index: Int, into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard output.freeCapacity >= 16 else {
      throw .register
    }
    withUnsafeBytes(of: state.vector) { bytes in
      for offset in 0 ..< 16 {
        output.append(bytes[index * 16 + offset])
      }
    }
  }

  private static func vector(_ state: inout DarwinARM64RegisterState,
                             index: Int, bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    guard bytes.count == 16 else {
      throw .register
    }
    withUnsafeMutableBytes(of: &state.vector) { storage in
      for offset in 0 ..< 16 {
        storage[index * 16 + offset] = bytes[offset]
      }
    }
  }

  private static func append(_ value: UInt64, size: Int,
                             into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard output.freeCapacity >= size else {
      throw .register
    }
    for index in 0 ..< size {
      output.append(UInt8(truncatingIfNeeded: value >> (index * 8)))
    }
  }

  private static func value(_ bytes: borrowing Span<UInt8>, size: Int)
      throws(Debuggee.Error) -> UInt64 {
    guard bytes.count == size else {
      throw .register
    }
    var value: UInt64 = 0
    for index in 0 ..< size {
      value |= UInt64(bytes[index]) << (index * 8)
    }
    return value
  }

}
#endif
