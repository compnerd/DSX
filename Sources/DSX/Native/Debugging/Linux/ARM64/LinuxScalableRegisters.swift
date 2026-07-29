// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

/// NT_ARM_SVE starts with user_sve_header. VL is in bytes, VG in 64-bit units.
internal struct LinuxSVEHeader: Sendable {
  internal enum Format {
    case inactive
    case fpsimd
    case full
  }

  internal static let kVectors = 32
  internal static let kPredicates = 17 // P0–P15 and FFR.
  internal static let kQuadword = 16
  internal static let kControls = 8 // FPSR and FPCR.
  internal static let kPayload = MemoryLayout<LinuxSVEHeader>.size
  internal static let kFPSIMDControl = kPayload + kVectors * kQuadword
  internal static let kFPSIMDSize = kFPSIMDControl + kQuadword

  internal var size: UInt32 = 0
  internal var maximum: UInt32 = 0
  internal var length: UInt16 = 0
  internal var limit: UInt16 = 0
  internal var flags: UInt16 = 0
  internal var reserved: UInt16 = 0

  internal var valid: Bool {
    length >= 16 && length <= 256 && length % 16 == 0 && limit >= length &&
        size >= minimum
  }

  internal var format: Format {
    switch (Int(size), flags & SVE_PT_REGS_SVE) {
    case (LinuxSVEHeader.kPayload, _): .inactive
    case (_, 0): .fpsimd
    default: .full
    }
  }

  internal var minimum: Int {
    switch format {
    case .inactive: LinuxSVEHeader.kPayload
    case .fpsimd: LinuxSVEHeader.kFPSIMDSize
    case .full: capacity
    }
  }

  internal var control: Int {
    let vectors = LinuxSVEHeader.kVectors * Int(length)
    let predicates = LinuxSVEHeader.kPredicates * Int(length) / 8
    let alignment = LinuxSVEHeader.kQuadword - 1
    let end = LinuxSVEHeader.kPayload + vectors + predicates
    return (end + alignment) & ~alignment
  }

  internal var capacity: Int {
    control + LinuxSVEHeader.kQuadword
  }
}

internal struct LinuxScalableRegisters: Sendable {
  private typealias Failure = Debuggee.Error

  private var header: LinuxSVEHeader
  private var bytes: Array<UInt8>
  private var dirty = false

  internal var length: Int {
    header.format == .inactive ? 0 : Int(header.length)
  }

  internal mutating func preserve() {
    dirty = header.format != .inactive
  }

  internal init?(_ thread: pid_t) throws(Debuggee.Error) {
    var initial = LinuxSVEHeader()
    do {
      _ = try withUnsafeMutableBytes(of: &initial, { bytes throws(Failure) in
        try bytes.transfer(PTRACE_GETREGSET, note: NT_ARM_SVE, thread: thread,
                           failure: { code in
          switch code {
          case EINVAL, EIO, ENODEV: .unsupported
          default: Debuggee.Error(register: code)
          }
        })
      })
    } catch .unsupported {
      return nil
    }
    guard initial.valid else {
      throw .register
    }
    header = initial
    if header.format == .inactive {
      // NT_ARM_SVE has no payload while SME streaming state is active. Keep
      // this distinct from an unsupported regset: do not fall back to writes
      // through NT_FPREGSET, which would alter state we have not captured.
      bytes = []
      return
    }
    bytes = Array(repeating: 0, count: header.capacity)
    try transfer(PTRACE_GETREGSET, thread: thread)
    if header.format == .fpsimd {
      // Expand the FPSIMD representation backwards to preserve overlapping Vn.
      for index in (0 ..< LinuxSVEHeader.kControls).reversed() {
        let source = LinuxSVEHeader.kFPSIMDControl + index
        bytes[header.control + index] = bytes[source]
      }
      for register in (0 ..< 32).reversed() {
        for index in (0 ..< length).reversed() {
          bytes[16 + register * length + index] =
              index < 16 ? bytes[16 + register * 16 + index] : 0
        }
      }
      for index in (16 + 32 * length) ..< header.control {
        bytes[index] = 0
      }
      header.flags |= SVE_PT_REGS_SVE
      header.size = UInt32(bytes.count)
    }
  }

  internal func read(_ identifier: UInt32, into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard header.format != .inactive else {
      throw .register
    }
    if identifier == ARM64Register.vg.rawValue {
      return try output.append(UInt64(length / 8), size: 8)
    }
    let range = try range(identifier)
    guard output.freeCapacity >= range.count else {
      throw .register
    }
    for index in range {
      output.append(bytes[index])
    }
  }

  internal mutating func write(_ identifier: UInt32,
                               bytes source: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    guard header.format != .inactive else {
      throw .register
    }
    if identifier == ARM64Register.vg.rawValue {
      let granules = try source.register(as: UInt64.self)
      guard granules >= 2, granules <= UInt64(header.limit) / 8,
          granules <= 32, granules % 2 == 0 else {
        throw .register
      }
      if granules == UInt64(length / 8) {
        return
      }
      // Vector-length changes invalidate scalable state (Linux's ABI).
      let width = Int(granules) * 8
      var resized = header
      resized.length = UInt16(width)
      var replacement = Array<UInt8>(repeating: 0, count: resized.capacity)
      for register in 0 ..< 32 {
        for index in 0 ..< 16 {
          replacement[16 + register * width + index] =
              bytes[16 + register * length + index]
        }
      }
      for index in 0 ..< LinuxSVEHeader.kControls {
        replacement[resized.control + index] = bytes[header.control + index]
      }
      header = resized
      bytes = replacement
    } else {
      let range = try range(identifier)
      guard source.count == range.count else {
        throw .register
      }
      for index in 0 ..< source.count {
        bytes[range.lowerBound + index] = source[index]
      }
    }
    dirty = true
  }

  private func range(_ identifier: UInt32) throws(Debuggee.Error)
      -> Range<Int> {
    let floating = ARM64Register.v0.rawValue
    let vectors = ARM64Register.z0.rawValue
    let predicates = ARM64Register.p0.rawValue
    let start = LinuxSVEHeader.kPayload + LinuxSVEHeader.kVectors * length
    let location = switch identifier {
    case floating ... ARM64Register.v31.rawValue:
      (LinuxSVEHeader.kPayload + Int(identifier - floating) * length,
       LinuxSVEHeader.kQuadword)
    case ARM64Register.fpsr.rawValue: (header.control, 4)
    case ARM64Register.fpcr.rawValue: (header.control + 4, 4)
    case vectors ..< predicates:
      (LinuxSVEHeader.kPayload + Int(identifier - vectors) * length, length)
    case predicates ... ARM64Register.ffr.rawValue:
      (start + Int(identifier - predicates) * length / 8, length / 8)
    default: throw Debuggee.Error.register
    }
    return location.0 ..< (location.0 + location.1)
  }

  internal mutating func commit(_ thread: pid_t) throws(Debuggee.Error) {
    guard dirty else {
      return
    }
    // Set the length using a header-only write first. The kernel may round it
    // down; never apply a payload using a layout the kernel did not accept.
    var requested = header
    requested.size = UInt32(bytes.count)
    _ = try withUnsafeMutableBytes(of: &requested, { bytes throws(Failure) in
      try bytes.transfer(PTRACE_SETREGSET, note: NT_ARM_SVE, thread: thread)
    })
    _ = try withUnsafeMutableBytes(of: &requested, { bytes throws(Failure) in
      try bytes.transfer(PTRACE_GETREGSET, note: NT_ARM_SVE, thread: thread)
    })
    guard requested.length == header.length else {
      throw .register
    }
    header.size = UInt32(bytes.count)
    withUnsafeBytes(of: header) { header in
      for index in 0 ..< header.count {
        bytes[index] = header[index]
      }
    }
    try transfer(PTRACE_SETREGSET, thread: thread)
  }

  private mutating func transfer(_ request: CInt, thread: pid_t)
      throws(Debuggee.Error) {
    let count =
        try bytes.withUnsafeMutableBufferPointer { raw throws(Failure) in
      try UnsafeMutableRawBufferPointer(raw)
        .transfer(request, note: NT_ARM_SVE, thread: thread, complete: false)
    }
    if request == PTRACE_GETREGSET {
      guard count >= LinuxSVEHeader.kPayload else {
        throw .register
      }
      let received = bytes.withUnsafeBytes {
        $0.loadUnaligned(as: LinuxSVEHeader.self)
      }
      guard received.valid, received.length == header.length,
          received.format != .inactive, count >= received.minimum else {
        throw .register
      }
      header = received
    } else {
      guard count == bytes.count else {
        throw .register
      }
    }
  }
}
#endif
