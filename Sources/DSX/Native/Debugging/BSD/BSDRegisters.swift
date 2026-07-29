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

extension BSDRegisterState {
  internal static func synchronize(_: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
  }

  internal init(_ identifier: ProcessThreadIdentifier) throws(Debuggee.Error) {
    let thread = try identifier.native
    var general = InlineArray<192, UInt8> { _ in 0 }
    try BSDRegisterState.transfer(PT_GETREGS, thread: thread, value: &general)
    var floating = InlineArray<512, UInt8> { _ in 0 }
    try BSDRegisterState.transfer(PT_GETFPREGS, thread: thread,
                                  value: &floating)
    self.init(thread: thread, general: general, floating: floating)
  }

  internal func read(_ register: RegisterIdentifier,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 23:
      let location = try BSDX86RegisterLayout(register)
      if location.native == location.size {
        try output.append(general, offset: location.offset, size: location.size)
      } else {
        try output.extend(general, offset: location.offset,
                          native: location.native, size: location.size)
      }
    case 24 ... 31:
      let offset = 32 + Int(register.rawValue - 24) * 16
      try output.append(floating, offset: offset, size: 10)
    case 32:
      try output.extend(floating, offset: 0, native: 2, size: 4)
    case 33:
      try output.extend(floating, offset: 2, native: 2, size: 4)
    case 34:
      try output.extend(floating, offset: 4, native: 1, size: 4)
    case 35, 37:
      try output.append(UInt32(0), size: 4)
    case 36:
      try output.append(floating, offset: 8, size: 4)
    case 38:
      try output.append(floating, offset: 16, size: 4)
    case 39:
      try output.extend(floating, offset: 6, native: 2, size: 4)
    case 40 ... 55:
      let offset = 160 + Int(register.rawValue - 40) * 16
      try output.append(floating, offset: offset, size: 16)
    case 56:
      try output.append(floating, offset: 24, size: 4)
    default:
      throw .register
    }
  }

  internal mutating func write(_ register: RegisterIdentifier,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    switch register.rawValue {
    case 0 ... 23:
      let location = try BSDX86RegisterLayout(register)
      if location.native == location.size {
        try bytes.write(offset: location.offset, to: &general)
      } else {
        try bytes.narrow(offset: location.offset, native: location.native,
                         size: location.size, to: &general)
      }
    case 24 ... 31:
      let offset = 32 + Int(register.rawValue - 24) * 16
      try bytes.write(offset: offset, to: &floating)
    case 32:
      try bytes.narrow(offset: 0, native: 2, size: 4, to: &floating)
    case 33:
      try bytes.narrow(offset: 2, native: 2, size: 4, to: &floating)
    case 34:
      try bytes.narrow(offset: 4, native: 1, size: 4, to: &floating)
    case 35, 37:
      guard bytes.count == 4 else {
        throw .register
      }
    case 36:
      try bytes.write(offset: 8, to: &floating)
    case 38:
      try bytes.write(offset: 16, to: &floating)
    case 39:
      try bytes.narrow(offset: 6, native: 2, size: 4, to: &floating)
    case 40 ... 55:
      let offset = 160 + Int(register.rawValue - 40) * 16
      try bytes.write(offset: offset, to: &floating)
    case 56:
      try bytes.write(offset: 24, to: &floating)
    default:
      throw .register
    }
  }

  internal consuming func commit(_ identifier: ProcessThreadIdentifier)
      throws(Debuggee.Error) {
    guard try thread == identifier.native else {
      throw .thread
    }
    try BSDRegisterState.transfer(PT_SETREGS, thread: thread, value: &general)
    try BSDRegisterState.transfer(PT_SETFPREGS, thread: thread,
                                  value: &floating)
  }

  private static func transfer<Value>(_ request: CInt, thread: pid_t,
                                      value: inout Value)
      throws(Debuggee.Error) {
    let result = withUnsafeMutablePointer(to: &value) { value in
      let pointer = UnsafeMutableRawPointer(value)
        .assumingMemoryBound(to: CChar.self)
      return ptrace(request, thread, pointer, 0)
    }
    guard result == 0 else {
      throw failure(errno)
    }
  }

  private static func failure(_ code: CInt) -> Debuggee.Error {
    switch code {
    case EINVAL: .unsupported
    default: Debuggee.Error(unix: code, invalid: .thread, support: true)
    }
  }
}
#endif
