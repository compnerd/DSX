// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc

internal enum BSDMemory {
  private typealias Failure = Debuggee.Error

  internal static func read(_ process: ProcessIdentifier,
                            address: Debuggee.Address, size: Int,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard size >= 0 else {
      throw .memory
    }
    let process = try process.native
    try output.withUnsafeMutableBufferPointer { data, index throws(Failure) in
      let count = min(size, data.count - index)
      let offset = try UnsafeMutableRawPointer(bitPattern: address.native)
      let destination = data.baseAddress!.advanced(by: index)
      var descriptor = ptrace_io_desc(piod_op: PIOD_READ_D, piod_offs: offset,
                                      piod_addr: destination, piod_len: count)
      try transfer(process, descriptor: &descriptor)
      index += descriptor.piod_len
    }
  }

  internal static func write(_ process: ProcessIdentifier,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> Int {
    let process = try process.native
    return try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      let offset = try UnsafeMutableRawPointer(bitPattern: address.native)
      let source = UnsafeMutableRawPointer(mutating: bytes.baseAddress)
      var descriptor = ptrace_io_desc(piod_op: PIOD_WRITE_D, piod_offs: offset,
                                      piod_addr: source, piod_len: bytes.count)
      try transfer(process, descriptor: &descriptor)
      return descriptor.piod_len
    }
  }

  internal static func region(_ process: ProcessIdentifier,
                              address: Debuggee.Address)
      throws(Debuggee.Error) -> Debuggee.MemoryRegion {
    throw .unsupported
  }

  internal static func allocate(_: ProcessIdentifier, size _: UInt64,
                                readable _: Bool, writable _: Bool,
                                executable _: Bool,
                                control _: inout BSDDebugControl)
      throws(Debuggee.Error) -> Debuggee.Address {
    throw .unsupported
  }

  internal static func deallocate(_: ProcessIdentifier,
                                  address _: Debuggee.Address, size _: UInt64,
                                  control _: inout BSDDebugControl)
      throws(Debuggee.Error) {
    throw .unsupported
  }
}

private func transfer(_ process: pid_t, descriptor: inout ptrace_io_desc)
    throws(Debuggee.Error) {
  let status = withUnsafeMutablePointer(to: &descriptor) { descriptor in
    descriptor.withMemoryRebound(to: CChar.self, capacity: 1) {
      ptrace(PT_IO, process, $0, 0)
    }
  }
  guard status == 0 else {
    throw UnixError.memory(errno)
  }
}
#endif
