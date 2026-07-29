// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

internal enum LinuxMemory {
  private typealias Failure = Debuggee.Error

  internal static func allocate(_ process: ProcessIdentifier, size: UInt64,
                                readable: Bool, writable: Bool,
                                executable: Bool,
                                control: inout LinuxDebugControl)
      throws(Debuggee.Error) -> Debuggee.Address {
    guard size > 0 else {
      throw .memory
    }
    if ABI.width == .b128 {
      throw .memory
    }
    if ABI.width == .b32, size > UInt64(UInt32.max) {
      throw .memory
    }
    let protection = (readable ? UInt64(PROT_READ) : 0)
                   | (writable ? UInt64(PROT_WRITE) : 0)
                   | (executable ? UInt64(PROT_EXEC) : 0)
    let flags = UInt64(MAP_PRIVATE | MAP_ANONYMOUS)
    var arguments = InlineArray<7, UInt64> { _ in 0 }
    arguments[0] = ABI.map
    arguments[2] = size
    arguments[3] = protection
    arguments[4] = flags
    arguments[5] = UInt64.max
    let raw = try control.syscall(process, arguments: arguments.span)
    return Debuggee.Address(rawValue: raw)
  }

  internal static func deallocate(_ process: ProcessIdentifier,
                                  address: Debuggee.Address, size: UInt64,
                                  control: inout LinuxDebugControl)
      throws(Debuggee.Error) {
    _ = try address.native
    guard size <= UInt64(UInt.max) else {
      throw .memory
    }
    var arguments = InlineArray<3, UInt64> { _ in 0 }
    arguments[0] = ABI.unmap
    arguments[1] = address.rawValue
    arguments[2] = size
    let result = try control.syscall(process, arguments: arguments.span)
    guard result == 0 else {
      throw .memory
    }
  }

  internal static func read(_ process: ProcessIdentifier,
                            address: Debuggee.Address, size: Int,
                            mapping: Debuggee.MemoryRegion? = nil,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard size >= 0 else {
      throw .memory
    }
    let identifier = try process.native
    let raw = address.rawValue
    let mapping = if let mapping {
      mapping
    } else {
      try region(process, address: address)
    }
    guard mapping.readable, mapping.address.rawValue <= raw else {
      throw .memory
    }
    let displacement = raw - mapping.address.rawValue
    guard displacement < mapping.size else {
      throw .memory
    }
    let available = min(mapping.size - displacement, UInt64(Int.max))
    try output.withUnsafeMutableBufferPointer { data, offset throws(Failure) in
      let requested = min(size, data.count - offset, Int(available))
      var local =
          iovec(iov_base: data.baseAddress!.advanced(by: offset),
                iov_len: numericCast(requested))
      let address = try UnsafeMutableRawPointer(bitPattern: address.native)
      var remote = iovec(iov_base: address, iov_len: numericCast(requested))
      let count = process_vm_readv(identifier, &local, 1, &remote, 1, 0)
      if count >= 0 {
        offset += count
        return
      }
      let thread = try thread(process, fallback: identifier)
      try DSX::read(thread, address: raw, size: requested, into: data,
                    offset: &offset)
    }
  }

  internal static func write(_ process: ProcessIdentifier,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>, count: inout Int)
      throws(Debuggee.Error) {
    count = 0
    let identifier = try process.native
    count = try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      let source = UnsafeMutableRawPointer(mutating: bytes.baseAddress)
      var local = iovec(iov_base: source, iov_len: numericCast(bytes.count))
      let destination = try UnsafeMutableRawPointer(bitPattern: address.native)
      var remote =
          iovec(iov_base: destination, iov_len: numericCast(bytes.count))
      let count = process_vm_writev(identifier, &local, 1, &remote, 1, 0)
      if count >= 0 {
        return count
      }
      let thread = try thread(process, fallback: identifier)
      return try DSX::write(thread, address: address.rawValue, bytes: bytes)
    }
  }

  internal static func patch(_ process: ProcessIdentifier,
                             thread: ProcessThreadIdentifier?,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>, count: inout Int)
      throws(Debuggee.Error) {
    count = 0
    let target = try LinuxMemory.target(process, thread: thread)
    count = try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      try DSX::write(target, address: address.rawValue, bytes: bytes)
    }
  }

  @_transparent
  private static func target(_ process: ProcessIdentifier,
                             thread: ProcessThreadIdentifier?)
      throws(Debuggee.Error) -> pid_t {
    if let thread {
      guard thread.process == process else {
        throw .thread
      }
      return try thread.thread.native
    }
    let identifier = try process.native
    return try DSX::thread(process, fallback: identifier)
  }

  internal static func region(_ process: ProcessIdentifier,
                              address: Debuggee.Address) throws(Debuggee.Error)
      -> Debuggee.MemoryRegion {
    _ = try address.native
    let leader = try process.native
    let identifier = try thread(process, fallback: leader)
    let bytes = try LinuxProcFS.contents("/proc/\(identifier)/maps")
    var maps = LinuxMemoryMapReader(bytes.span)
    while let map = maps.next() {
      if address.rawValue < map.start.rawValue {
        let size = map.start.rawValue - address.rawValue
        return Debuggee.MemoryRegion(address: address, size: size,
                                     readable: false, writable: false,
                                     executable: false)
      }
      guard address.rawValue < map.end.rawValue else {
        continue
      }
      return Debuggee.MemoryRegion(address: map.start,
                                   size: map.end.rawValue - map.start.rawValue,
                                   readable: map.readable,
                                   writable: map.writable,
                                   executable: map.executable,
                                   name: maps.path(map))
    }
    return Debuggee.MemoryRegion(address: address,
                                 size: UInt64.max - address.rawValue,
                                 readable: false, writable: false,
                                 executable: false)
  }
}

private func thread(_ process: ProcessIdentifier, fallback: pid_t)
    throws(Debuggee.Error) -> pid_t {
  let leader = ThreadIdentifier(rawValue: process.rawValue)
  let identifier = ProcessThreadIdentifier(process: process, thread: leader)
  if try identifier.alive {
    return fallback
  }
  guard let identifier = try process.threads.first else {
    throw .process
  }
  return try identifier.thread.native
}

private func read(_ process: pid_t, address: UInt64, size: Int,
                  into output: UnsafeMutableBufferPointer<UInt8>,
                  offset: inout Int) throws(Debuggee.Error) {
  let width = MemoryLayout<CLong>.size
  var copied = 0
  while copied < size {
    let (current, overflow) = address.addingReportingOverflow(UInt64(copied))
    if overflow {
      throw .memory
    }
    let aligned = current & ~UInt64(width - 1)
    let displacement = Int(current - aligned)
    let count = min(size - copied, width - displacement)
    do throws(Debuggee.Error) {
      var word = try peek(process, address: aligned)
      withUnsafeBytes(of: &word) { word in
        for index in 0 ..< count {
          output[offset + index] = word[displacement + index]
        }
      }
      offset += count
      copied += count
    } catch {
      if copied > 0 {
        return
      }
      throw error
    }
  }
}

private func write(_ process: pid_t, address: UInt64,
                   bytes: UnsafeRawBufferPointer) throws(Debuggee.Error)
    -> Int {
  let width = MemoryLayout<CLong>.size
  var copied = 0
  while copied < bytes.count {
    let (current, overflow) = address.addingReportingOverflow(UInt64(copied))
    if overflow {
      throw .memory
    }
    let aligned = current & ~UInt64(width - 1)
    let displacement = Int(current - aligned)
    let count = min(bytes.count - copied, width - displacement)
    do throws(Debuggee.Error) {
      var word: CLong = if displacement == 0, count == width {
        0
      } else {
        try peek(process, address: aligned)
      }
      withUnsafeMutableBytes(of: &word) { word in
        for index in 0 ..< count {
          word[displacement + index] = bytes[copied + index]
        }
      }
      try poke(process, address: aligned, word: word)
      copied += count
    } catch {
      if copied > 0 {
        return copied
      }
      throw error
    }
  }
  return copied
}

private func peek(_ process: pid_t, address: UInt64) throws(Debuggee.Error)
    -> CLong {
  errno = 0
  let value = try Debuggee.Address(rawValue: address).native
  let address = UnsafeMutableRawPointer(bitPattern: value)
  let word = ptrace(PTRACE_PEEKDATA, process, address, nil)
  if word == -1, errno != 0 {
    throw LinuxProcFS.failure(errno)
  }
  return word
}

private func poke(_ process: pid_t, address: UInt64, word: CLong)
    throws(Debuggee.Error) {
  let value = try Debuggee.Address(rawValue: address).native
  let address = UnsafeMutableRawPointer(bitPattern: value)
  let data = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: word))
  guard ptrace(PTRACE_POKEDATA, process, address, data) == 0 else {
    throw LinuxProcFS.failure(errno)
  }
}
#endif
