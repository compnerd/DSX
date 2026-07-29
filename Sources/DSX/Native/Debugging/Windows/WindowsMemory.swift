// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import WinSDK

internal enum WindowsMemory {
  private typealias Failure = Debuggee.Error

  internal static func read(_ process: ProcessIdentifier,
                            address: Debuggee.Address, size: Int,
                            into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard size >= 0 else {
      throw .memory
    }
    let access = PROCESS_VM_READ | PROCESS_QUERY_LIMITED_INFORMATION
    let handle = try open(process, access: access)
    var info = MEMORY_BASIC_INFORMATION()
    let width = SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size)
    let queried =
        try VirtualQueryEx(handle.value, pointer(address), &info, width)
    guard queried == width else {
      throw WindowsError.memory(GetLastError())
    }
    let protection = info.Protect
    let accessible = info.State == MEM_COMMIT &&
        protection & (PAGE_GUARD | PAGE_NOACCESS) == 0
    guard accessible && readable(protection) else {
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
      var count: SIZE_T = 0
      let requested = min(size, data.count - offset, Int(available))
      let status = try ReadProcessMemory(handle.value, pointer(address),
                                         data.baseAddress!.advanced(by: offset),
                                         SIZE_T(requested), &count)
      if status || count > 0 {
        offset += Int(count)
        return
      }
      throw WindowsError.memory(GetLastError())
    }
  }

  @inline(never)
  internal static func write(_ process: ProcessIdentifier,
                             address: Debuggee.Address,
                             bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) -> Int {
    guard bytes.count > 0 else {
      return 0
    }
    let query = PROCESS_QUERY_LIMITED_INFORMATION
    let access = PROCESS_VM_OPERATION | PROCESS_VM_WRITE | query
    let handle = try open(process, access: access)
    return try bytes.withUnsafeBytes { bytes throws(Debuggee.Error) in
      var offset = 0
      while offset < bytes.count {
        let (raw, overflow) =
            address.rawValue.addingReportingOverflow(UInt64(offset))
        if overflow {
          throw .memory
        }
        let location = Debuggee.Address(rawValue: raw)
        let remaining = UnsafeRawBufferPointer(rebasing: bytes[offset...])
        let count = try transfer(handle, address: location, bytes: remaining)
        offset += count
        if count == 0 {
          break
        }
      }
      return offset
    }
  }
}

private func transfer(_ handle: borrowing WindowsHandle,
                      address: Debuggee.Address, bytes: UnsafeRawBufferPointer)
    throws(Debuggee.Error) -> Int {
  var info = MEMORY_BASIC_INFORMATION()
  let size = SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size)
  let queried = try VirtualQueryEx(handle.value, pointer(address), &info, size)
  guard queried == size else {
    throw WindowsError.memory(GetLastError())
  }
  let base = UInt64(UInt(bitPattern: info.BaseAddress))
  let available = UInt64(info.RegionSize) - (address.rawValue - base)
  let count = min(bytes.count, Int(clamping: available))
  let bytes = UnsafeRawBufferPointer(rebasing: bytes[..<count])
  let protection = info.Protect
  let execute = executable(protection)
  if writable(protection) {
    return try store(handle, address: address, bytes: bytes, flush: execute)
  }
  let temporary = execute ? PAGE_EXECUTE_READWRITE : PAGE_READWRITE
  var previous: DWORD = 0
  guard try VirtualProtectEx(handle.value, pointer(address), SIZE_T(count),
                             temporary, &previous) else {
    throw WindowsError.memory(GetLastError())
  }
  let result: Result<Int, Debuggee.Error>
  do throws(Debuggee.Error) {
    result = try .success(store(handle, address: address, bytes: bytes,
                                flush: execute))
  } catch {
    result = .failure(error)
  }
  var restored: DWORD = 0
  guard try VirtualProtectEx(handle.value, pointer(address), SIZE_T(count),
                             previous, &restored) else {
    throw WindowsError.memory(GetLastError())
  }
  return try result.get()
}

private func store(_ handle: borrowing WindowsHandle, address: Debuggee.Address,
                   bytes: UnsafeRawBufferPointer,
                   flush: Bool) throws(Debuggee.Error) -> Int {
  var count: SIZE_T = 0
  let status = try WriteProcessMemory(handle.value, pointer(address),
                                      bytes.baseAddress, SIZE_T(bytes.count),
                                      &count)
  guard status else {
    throw WindowsError.memory(GetLastError())
  }
  if flush {
    guard try FlushInstructionCache(handle.value, pointer(address),
                                    count) else {
      throw WindowsError.memory(GetLastError())
    }
  }
  return Int(count)
}

extension WindowsMemory {
  internal static func region(_ process: ProcessIdentifier,
                              address: Debuggee.Address)
      throws(Debuggee.Error) -> Debuggee.MemoryRegion {
    let handle = try open(process, access: PROCESS_QUERY_LIMITED_INFORMATION)
    var info = MEMORY_BASIC_INFORMATION()
    let capacity = SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size)
    let count =
        try VirtualQueryEx(handle.value, pointer(address), &info, capacity)
    guard count == capacity else {
      let code = GetLastError()
      if code == ERROR_INVALID_PARAMETER, terminal(address) {
        return Debuggee.MemoryRegion(address: address,
                                     size: UInt64.max - address.rawValue,
                                     readable: false, writable: false,
                                     executable: false)
      }
      throw WindowsError.memory(code)
    }
    let protection = info.Protect
    let accessible = info.State == MEM_COMMIT &&
        protection & (PAGE_GUARD | PAGE_NOACCESS) == 0
    let base = UInt64(UInt(bitPattern: info.BaseAddress))
    let address = Debuggee.Address(rawValue: base)
    let size = UInt64(info.RegionSize)
    return Debuggee.MemoryRegion(address: address, size: size,
                                 readable: accessible && readable(protection),
                                 writable: accessible && writable(protection),
                                 executable: accessible &&
                                     executable(protection))
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
    let handle = try open(process, access: access)
    let protection =
        protect(readable: readable, writable: writable, executable: executable)
    guard protection > 0 else {
      throw .memory
    }
    let address = VirtualAllocEx(handle.value, nil, SIZE_T(size),
                                 MEM_COMMIT | MEM_RESERVE, protection)
    guard let address else {
      throw WindowsError.memory(GetLastError())
    }
    return Debuggee.Address(rawValue: UInt64(UInt(bitPattern: address)))
  }

  internal static func deallocate(_ process: ProcessIdentifier,
                                  address: Debuggee.Address, size _: UInt64,
                                  control _: inout WindowsDebugControl)
      throws(Debuggee.Error) {
    let handle = try open(process, access: PROCESS_VM_OPERATION)
    guard try VirtualFreeEx(handle.value, pointer(address), 0,
                            MEM_RELEASE) else {
      throw WindowsError.memory(GetLastError())
    }
  }
}

private func open(_ process: ProcessIdentifier, access: DWORD)
    throws(Debuggee.Error) -> WindowsHandle {
  let identifier = try process.native
  guard let handle = OpenProcess(access, false, identifier) else {
    throw WindowsError.memory(GetLastError())
  }
  return WindowsHandle(handle)
}

private func pointer(_ address: Debuggee.Address) throws(Debuggee.Error)
    -> UnsafeMutableRawPointer? {
  try UnsafeMutableRawPointer(bitPattern: address.native)
}

private func terminal(_ address: Debuggee.Address) -> Bool {
  var info = SYSTEM_INFO()
  GetNativeSystemInfo(&info)
  guard let maximum = info.lpMaximumApplicationAddress else {
    return false
  }
  let limit = UInt64(UInt(bitPattern: maximum))
  return address.rawValue >= limit && address.rawValue < UInt64.max
}

private func readable(_ protection: DWORD) -> Bool {
  switch protection & 0xff {
  case PAGE_READONLY, PAGE_READWRITE, PAGE_WRITECOPY, PAGE_EXECUTE_READ,
       PAGE_EXECUTE_READWRITE, PAGE_EXECUTE_WRITECOPY:
    true
  default:
    false
  }
}

private func writable(_ protection: DWORD) -> Bool {
  switch protection & 0xff {
  case PAGE_READWRITE, PAGE_WRITECOPY, PAGE_EXECUTE_READWRITE,
       PAGE_EXECUTE_WRITECOPY:
    true
  default:
    false
  }
}

private func executable(_ protection: DWORD) -> Bool {
  switch protection & 0xff {
  case PAGE_EXECUTE, PAGE_EXECUTE_READ, PAGE_EXECUTE_READWRITE,
       PAGE_EXECUTE_WRITECOPY:
    true
  default:
    false
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
