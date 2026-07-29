// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS) && arch(arm64)
internal import Darwin

internal struct DarwinARM64RegisterState: ~Copyable {
  private let thread: DarwinThread
  private var general: arm_thread_state64_t
  private var vector: arm_neon_state64_t
  private var exception: arm_exception_state64_t
}

extension DarwinARM64RegisterState {
  internal static func synchronize(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    let thread = try DarwinThread(identifier)
    try thread.synchronize()
  }

  internal init(_ identifier: ProcessThreadIdentifier) throws(Debuggee.Error) {
    let thread = try DarwinThread(identifier)
    let general = try arm_thread_state64_t(thread.handle)
    var vector = arm_neon_state64_t()
    let exception = try arm_exception_state64_t(thread.handle)
    try thread.handle.read(&vector, flavor: ARM_NEON_STATE64)
    self.thread = consume thread
    self.general = general
    self.vector = vector
    self.exception = exception
  }

  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 28:
      let offset = Int(register.rawValue) * 8
      try output.append(general.__x, offset: offset, size: 8)
    case 29:
      try output.append(general.__fp, size: 8)
    case 30:
      try output.append(general.__lr, size: 8)
    case 31:
      try output.append(general.__sp, size: 8)
    case 32:
      try output.append(general.__pc, size: 8)
    case 33:
      try output.append(UInt64(general.__cpsr), size: 4)
    case 34 ... 65:
      let offset = Int(register.rawValue - 34) * 16
      try output.append(vector, offset: offset, size: 16)
    case 66:
      try output.append(UInt64(vector.__fpsr), size: 4)
    case 67:
      try output.append(UInt64(vector.__fpcr), size: 4)
    case 162:
      try output.append(exception.__far, size: 8)
    case 163:
      try output.append(UInt64(exception.__esr), size: 4)
    case 164:
      try output.append(UInt64(exception.__exception), size: 4)
    default:
      throw .register
    }
  }

  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 28:
      let offset = Int(register.rawValue) * 8
      try bytes.narrow(offset: offset, native: 8, size: 8, to: &general.__x)
    case 29:
      general.__fp = try bytes.register(as: UInt64.self)
    case 30:
      general.__lr = try bytes.register(as: UInt64.self)
    case 31:
      general.__sp = try bytes.register(as: UInt64.self)
    case 32:
      general.__pc = try bytes.register(as: UInt64.self)
    case 33:
      general.__cpsr = try bytes.register(as: UInt32.self)
    case 34 ... 65:
      let offset = Int(register.rawValue - 34) * 16
      try bytes.narrow(offset: offset, native: 16, size: 16, to: &vector)
    case 66:
      vector.__fpsr = try bytes.register(as: UInt32.self)
    case 67:
      vector.__fpcr = try bytes.register(as: UInt32.self)
    case 162:
      exception.__far = try bytes.register(as: UInt64.self)
    case 163:
      exception.__esr = try bytes.register(as: UInt32.self)
    case 164:
      exception.__exception = try bytes.register(as: UInt32.self)
    default:
      throw .register
    }
  }

  internal consuming func commit(_: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    try thread.handle.write(general, flavor: ARM_THREAD_STATE64)
    try thread.handle.write(vector, flavor: ARM_NEON_STATE64)
    try thread.handle.write(exception, flavor: ARM_EXCEPTION_STATE64)
  }
}
#endif
