// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal enum WindowsMemory {
  private typealias Failure = Debuggee.Error

  internal static func read(_ process: ProcessIdentifier,
                            address: Debuggee.Address, size: Int,
                            mapping _: Debuggee.MemoryRegion? = nil,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard size >= 0 else {
      throw .memory
    }
    let access = PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION
    let handle = try WindowsHandle(process: process, access: access)
    var info = MEMORY_BASIC_INFORMATION()
    let width = SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size)
    let queried =
        try VirtualQueryEx(handle.value, pointer(address), &info, width)
    guard queried == width else {
      throw Debuggee.Error(memory: GetLastError())
    }
    guard info.accessible && info.readable else {
      throw .memory
    }
    let base = UInt64(UInt(bitPattern: info.BaseAddress))
    guard address.rawValue >= base else {
      throw .memory
    }
    let displacement = address.rawValue - base
    let region = UInt64(info.RegionSize)
    guard displacement < region else {
      throw .memory
    }
    let available = min(region - displacement, UInt64(Int.max))
    try output.withUnsafeMutableBufferPointer { data, offset throws(Failure) in
      guard let base = data.baseAddress else { return }
      var count: SIZE_T = 0
      let requested = min(size, data.count - offset, Int(available))
      let status = try ReadProcessMemory(handle.value, pointer(address),
                                         base.advanced(by: offset),
                                         SIZE_T(requested), &count)
      if status || count > 0 {
        offset += Int(count)
        return
      }
      throw Debuggee.Error(memory: GetLastError())
    }
  }

  @inline(never)
  internal static func write(_ process: ProcessIdentifier,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>, count: inout Int)
      throws(Debuggee.Error) {
    count = 0
    guard bytes.count > 0 else {
      return
    }
    let query = PROCESS_QUERY_LIMITED_INFORMATION
    let access = PROCESS_VM_OPERATION | PROCESS_VM_WRITE | query
    let handle = try WindowsHandle(process: process, access: access)
    try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      while count < bytes.count {
        let offset = count
        let (raw, overflow) =
            address.rawValue.addingReportingOverflow(UInt64(offset))
        if overflow {
          throw .memory
        }
        let location = Debuggee.Address(rawValue: raw)
        let remaining = UnsafeRawBufferPointer(rebasing: bytes[offset...])
        var restored = true
        do throws(Debuggee.Error) {
          try handle.transfer(address: location, bytes: remaining,
                              count: &count, restored: &restored)
        } catch {
          if restored, count == offset, offset > 0 {
            return
          }
          throw error
        }
        if count == offset {
          break
        }
      }
    }
  }

  internal static func patch(_ process: ProcessIdentifier,
                             thread _: ProcessThreadIdentifier?,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>, count: inout Int)
      throws(Debuggee.Error) {
    try write(process, address: address, bytes: bytes, count: &count)
  }
}

extension WindowsHandle {
  fileprivate init(process: ProcessIdentifier, access: DWORD)
      throws(Debuggee.Error) {
    let identifier = try process.native
    guard let handle = OpenProcess(access, false, identifier) else {
      throw Debuggee.Error(memory: GetLastError())
    }
    self.init(handle)
  }

  fileprivate func transfer(address: Debuggee.Address,
                            bytes: UnsafeRawBufferPointer,
                            count written: inout Int, restored: inout Bool)
      throws(Debuggee.Error) {
    var info = MEMORY_BASIC_INFORMATION()
    let size = SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size)
    let queried = try VirtualQueryEx(value, pointer(address), &info, size)
    guard queried == size else {
      throw Debuggee.Error(memory: GetLastError())
    }
    let base = UInt64(UInt(bitPattern: info.BaseAddress))
    let available = UInt64(info.RegionSize) - (address.rawValue - base)
    let count = min(bytes.count, Int(clamping: available))
    let bytes = UnsafeRawBufferPointer(rebasing: bytes[..<count])
    let execute = info.executable
    if info.writable {
      return try store(address: address, bytes: bytes, flush: execute,
                       count: &written)
    }
    let temporary = execute ? PAGE_EXECUTE_READWRITE : PAGE_READWRITE
    var previous: DWORD = 0
    guard try VirtualProtectEx(value, pointer(address), SIZE_T(count),
                               temporary, &previous) else {
      throw Debuggee.Error(memory: GetLastError())
    }
    restored = false
    let result: Result<Void, Debuggee.Error>
    do throws(Debuggee.Error) {
      result = try .success(store(address: address, bytes: bytes,
                                  flush: execute, count: &written))
    } catch {
      result = .failure(error)
    }
    var discarded: DWORD = 0
    guard try VirtualProtectEx(value, pointer(address), SIZE_T(count), previous,
                               &discarded) else {
      throw Debuggee.Error(memory: GetLastError())
    }
    restored = true
    return try result.get()
  }

  private func store(address: Debuggee.Address, bytes: UnsafeRawBufferPointer,
                     flush: Bool, count written: inout Int)
      throws(Debuggee.Error) {
    var count: SIZE_T = 0
    let status = try WriteProcessMemory(value, pointer(address),
                                        bytes.baseAddress, SIZE_T(bytes.count),
                                        &count)
    guard status || count > 0 else {
      throw Debuggee.Error(memory: GetLastError())
    }
    written += Int(count)
    if flush {
      guard try FlushInstructionCache(value, pointer(address), count) else {
        throw Debuggee.Error(memory: GetLastError())
      }
    }
  }
}

extension WindowsMemory {
  internal static func region(_ process: ProcessIdentifier,
                              address: Debuggee.Address) throws(Debuggee.Error)
      -> Debuggee.MemoryRegion {
    let access = PROCESS_QUERY_LIMITED_INFORMATION
    let handle = try WindowsHandle(process: process, access: access)
    var info = MEMORY_BASIC_INFORMATION()
    let capacity = SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size)
    let count =
        try VirtualQueryEx(handle.value, pointer(address), &info, capacity)
    guard count == capacity else {
      let code = GetLastError()
      // VirtualQueryEx reports the debuggee's address-space limit, which can
      // be lower than the host's (for example, a non-large-address-aware PE).
      if code == ERROR_INVALID_PARAMETER, address.rawValue < UInt64.max {
        return Debuggee.MemoryRegion(address: address,
                                     size: UInt64.max - address.rawValue,
                                     readable: false, writable: false,
                                     executable: false, mapped: false)
      }
      throw Debuggee.Error(memory: code)
    }
    let base = UInt64(UInt(bitPattern: info.BaseAddress))
    let address = Debuggee.Address(rawValue: base)
    let size = UInt64(info.RegionSize)
    let execute = info.accessible && info.executable
    return Debuggee.MemoryRegion(address: address, size: size,
                                 readable: info.accessible && info.readable,
                                 writable: info.accessible && info.writable,
                                 executable: execute,
                                 mapped: info.State == MEM_COMMIT)
  }

  internal static func allocate(_ process: ProcessIdentifier, size: UInt64,
                                readable: Bool, writable: Bool,
                                executable: Bool,
                                control _: inout WindowsDebugControl)
      throws(Debuggee.Error) -> Debuggee.Address {
    guard size <= UInt64(SIZE_T.max) else {
      throw .memory
    }
    let access = PROCESS_VM_OPERATION | PROCESS_QUERY_LIMITED_INFORMATION
    let handle = try WindowsHandle(process: process, access: access)
    let protection =
        protect(readable: readable, writable: writable, executable: executable)
    guard protection > 0 else {
      throw .memory
    }
    let address = VirtualAllocEx(handle.value, nil, SIZE_T(size),
                                 MEM_COMMIT | MEM_RESERVE, protection)
    guard let address else {
      throw Debuggee.Error(memory: GetLastError())
    }
    return Debuggee.Address(rawValue: UInt64(UInt(bitPattern: address)))
  }

  @inline(never)
  internal static func deallocate(_ process: ProcessIdentifier,
                                  address: Debuggee.Address, size _: UInt64,
                                  control _: inout WindowsDebugControl)
      throws(Debuggee.Error) {
    let handle =
        try WindowsHandle(process: process, access: PROCESS_VM_OPERATION)
    guard try VirtualFreeEx(handle.value, pointer(address), 0,
                            MEM_RELEASE) else {
      throw Debuggee.Error(memory: GetLastError())
    }
  }
}

private func pointer(_ address: Debuggee.Address) throws(Debuggee.Error)
    -> UnsafeMutableRawPointer? {
  try UnsafeMutableRawPointer(bitPattern: address.native)
}

extension MEMORY_BASIC_INFORMATION {
  fileprivate var accessible: Bool {
    State == MEM_COMMIT && Protect & (PAGE_GUARD | PAGE_NOACCESS) == 0
  }

  @inline(__always)
  fileprivate var readable: Bool {
    switch Protect & 0xff {
    case PAGE_READONLY, PAGE_READWRITE, PAGE_WRITECOPY, PAGE_EXECUTE_READ,
         PAGE_EXECUTE_READWRITE, PAGE_EXECUTE_WRITECOPY:
      true
    default:
      false
    }
  }

  @inline(__always)
  fileprivate var writable: Bool {
    switch Protect & 0xff {
    case PAGE_READWRITE, PAGE_WRITECOPY, PAGE_EXECUTE_READWRITE,
         PAGE_EXECUTE_WRITECOPY:
      true
    default:
      false
    }
  }

  fileprivate var executable: Bool {
    switch Protect & 0xff {
    case PAGE_EXECUTE, PAGE_EXECUTE_READ, PAGE_EXECUTE_READWRITE,
         PAGE_EXECUTE_WRITECOPY:
      true
    default:
      false
    }
  }
}

private func protect(readable: Bool, writable: Bool,
                     executable: Bool) -> DWORD {
  switch (readable, writable, executable) {
  case (true, true, true):
    PAGE_EXECUTE_READWRITE
  case (true, false, true):
    PAGE_EXECUTE_READ
  case (false, false, true):
    PAGE_EXECUTE
  case (true, true, false):
    PAGE_READWRITE
  case (true, false, false):
    PAGE_READONLY
  case (false, true, _):
    0
  case (false, false, false):
    PAGE_NOACCESS
  }
}
#endif
