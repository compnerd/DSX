// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc

internal enum BSDMemory {
  private typealias Failure = Debuggee.Error

  internal static func read(_ process: ProcessIdentifier,
                            address: Debuggee.Address, size: Int,
                            mapping _: Debuggee.MemoryRegion? = nil,
                            into output: inout OutputSpan<UInt8>,
                            control _: borrowing NativeDebugControl =
                                NativeDebugControl()) throws(Debuggee.Error) {
    guard size >= 0 else {
      throw .memory
    }
    let process = try process.native
    try output.withUnsafeMutableBufferPointer { data, index throws(Failure) in
      let count = min(size, data.count - index)
      let offset = try UnsafeMutableRawPointer(bitPattern: address.native)
      guard let base = data.baseAddress else { return }
      let destination = base.advanced(by: index)
      var descriptor = ptrace_io_desc(piod_op: PIOD_READ_D, piod_offs: offset,
                                      piod_addr: destination, piod_len: count)
      try descriptor.transfer(process)
      index += descriptor.piod_len
    }
  }

  internal static func write(_ process: ProcessIdentifier,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>, count: inout Int,
                             control _: borrowing NativeDebugControl =
                                 NativeDebugControl()) throws(Debuggee.Error) {
    count = 0
    let process = try process.native
    try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      let offset = try UnsafeMutableRawPointer(bitPattern: address.native)
      let source = UnsafeMutableRawPointer(mutating: bytes.baseAddress)
      var descriptor = ptrace_io_desc(piod_op: PIOD_WRITE_D, piod_offs: offset,
                                      piod_addr: source, piod_len: bytes.count)
      try descriptor.transfer(process)
      count = descriptor.piod_len
    }
  }

  internal static func patch(_ process: ProcessIdentifier,
                             thread _: ProcessThreadIdentifier?,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>, count: inout Int,
                             control _: borrowing NativeDebugControl =
                                 NativeDebugControl()) throws(Debuggee.Error) {
    try write(process, address: address, bytes: bytes, count: &count)
  }

  internal static func region(_ process: ProcessIdentifier,
                              address: Debuggee.Address,
                              control _: borrowing NativeDebugControl =
                                  NativeDebugControl()) throws(Debuggee.Error)
      -> Debuggee.MemoryRegion {
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

extension ptrace_io_desc {
  fileprivate mutating func transfer(_ process: pid_t) throws(Debuggee.Error) {
#if os(OpenBSD)
    // OpenBSD only copies piod_len back on success. Commit one page at a time
    // so a later inaccessible page cannot hide a completed read or write.
    let length = piod_len
    let address = UInt(bitPattern: piod_offs)
    guard UInt(length) <= UInt.max - address else {
      throw .memory
    }
    let page = UInt(getpagesize())
    var count = 0
    while count < length {
      let current = address + UInt(count)
      let size = min(length - count, Int(page - current % page))
      var portion = self
      portion.piod_offs = UnsafeMutableRawPointer(bitPattern: current)
      portion.piod_addr = piod_addr?.advanced(by: count)
      portion.piod_len = size
      do throws(Debuggee.Error) {
        try portion.perform(process)
      } catch {
        guard count > 0 else {
          throw error
        }
        break
      }
      count += portion.piod_len
      if portion.piod_len < size {
        break
      }
    }
    piod_len = count
#else
    try perform(process)
#endif
  }

  private mutating func perform(_ process: pid_t) throws(Debuggee.Error) {
    let status = withUnsafeMutablePointer(to: &self) { descriptor in
      descriptor.withMemoryRebound(to: CChar.self, capacity: 1) {
        ptrace(PT_IO, process, $0, 0)
      }
    }
    guard status == 0 else {
      throw Debuggee.Error(memory: errno)
    }
  }
}
#endif
