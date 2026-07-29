// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && (arch(i386) || arch(x86_64))
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

// NT_X86_XSTATE uses the standard, uncompacted XSAVE layout. Linux places
// the supported feature mask in the FXSAVE software-reserved area.
private let kSoftwareOffset = 464
private let kHeaderOffset = 512
private let kVectorOffset = 576
private let kVectorSize = 256
private let XFEATURE_MASK_FPSSE: UInt8 = 3
private let XFEATURE_MASK_YMM: UInt8 = 4

internal struct LinuxXState: Sendable {
  private var storage: Array<UInt8>

  internal init?(_ thread: pid_t) throws(Debuggee.Error) {
    var capacity = kVectorOffset + kVectorSize
    var storage: Array<UInt8>
    while true {
      storage = Array(repeating: 0, count: capacity)
      let length: Int
      do {
        length = try storage.withUnsafeMutableBufferPointer { bytes
            throws(Debuggee.Error) in
          try UnsafeMutableRawBufferPointer(bytes)
            .transfer(PTRACE_GETREGSET, note: NT_X86_XSTATE, thread: thread,
                      complete: false, failure: { code in
              switch code {
              case EINVAL, EIO, ENODEV: .unsupported
              default: Debuggee.Error(register: code)
              }
            })
        }
      } catch .unsupported {
        return nil
      }
      guard length >= kVectorOffset + kVectorSize,
          storage[kSoftwareOffset] & XFEATURE_MASK_YMM > 0 else {
        return nil
      }
      if length < capacity {
        storage.removeLast(capacity - length)
        break
      }
      // SETREGSET requires the entire image, including unexposed extensions.
      guard capacity <= Int.max / 2 else {
        throw .register
      }
      capacity *= 2
    }
    if storage[kHeaderOffset] & XFEATURE_MASK_YMM == 0 {
      for index in kVectorOffset ..< (kVectorOffset + kVectorSize) {
        storage[index] = 0
      }
    }
    self.storage = storage
  }

  internal func read(_ index: Int, into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard output.freeCapacity >= 16 else {
      throw .register
    }
    let offset = kVectorOffset + index * 16
    for index in offset ..< (offset + 16) {
      output.append(storage[index])
    }
  }

  internal mutating func write(_ index: Int, bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    guard bytes.count == 16 else {
      throw .register
    }
    let offset = kVectorOffset + index * 16
    for index in 0 ..< 16 {
      storage[offset + index] = bytes[index]
    }
    storage[kHeaderOffset] |= XFEATURE_MASK_YMM
  }

  internal mutating func commit(_ thread: pid_t,
                                floating: borrowing LinuxFloatingRegisters)
      throws(Debuggee.Error) {
    withUnsafeBytes(of: floating) { bytes in
      for index in 0 ..< kSoftwareOffset {
        storage[index] = bytes[index]
      }
    }
    storage[kHeaderOffset] |= XFEATURE_MASK_FPSSE
    _ = try storage.withUnsafeMutableBufferPointer { bytes
        throws(Debuggee.Error) in
      try UnsafeMutableRawBufferPointer(bytes)
        .transfer(PTRACE_SETREGSET, note: NT_X86_XSTATE, thread: thread)
    }
  }
}

extension LinuxRegisterState {
  internal var configuration: RegisterConfiguration {
    RegisterConfiguration(vector: extended != nil)
  }
}
#endif
