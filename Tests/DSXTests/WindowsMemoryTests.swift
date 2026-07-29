// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsMemoryTests {
  @Test
  internal func progress() throws {
    let process = GetCurrentProcess()
    var info = SYSTEM_INFO()
    GetSystemInfo(&info)
    let page = Int(info.dwPageSize)
    let memory = try #require(VirtualAllocEx(process, nil, SIZE_T(page * 2),
                                             DSX::MEM_RESERVE,
                                             DSX::PAGE_READWRITE))
    defer {
      _ = VirtualFreeEx(process, memory, 0, DSX::MEM_RELEASE)
    }
    try #require(VirtualAllocEx(process, memory, SIZE_T(page), DSX::MEM_COMMIT,
                                DSX::PAGE_READWRITE) != nil)
    let identifier = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let raw = UInt64(UInt(bitPattern: memory + page - 4))
    let address = Debuggee.Address(rawValue: raw)
    let site = ABI.breakpoint(address)
    var session = DebugSession()
    let breakpoint = try session.breakpoints.insert(identifier, site,
                                                    context: &session.control)
    let bytes: Array<UInt8> = [1, 2, 3, 4, 5, 6, 7, 8]
    #expect(try session.write(identifier, address: address, bytes: bytes.span)
        == 4)
    try session.breakpoints.remove(identifier, breakpoint,
                                   context: &session.control)
    let actual = (memory + page - 4).assumingMemoryBound(to: UInt8.self)
    #expect(Array(UnsafeBufferPointer(start: actual, count: 4)) == [1, 2, 3, 4])
  }

  @Test(arguments: [(DSX::PAGE_READONLY, DSX::PAGE_EXECUTE_READ),
                    (DSX::PAGE_EXECUTE_READ, DSX::PAGE_READONLY),
                    (DSX::PAGE_READWRITE, DSX::PAGE_READONLY)])
  internal func boundaries(_ protections: (DWORD, DWORD)) throws {
    let process = GetCurrentProcess()
    var info = SYSTEM_INFO()
    GetSystemInfo(&info)
    let page = Int(info.dwPageSize)
    let flags = DSX::MEM_RESERVE | DSX::MEM_COMMIT
    let memory = try #require(VirtualAllocEx(process, nil, SIZE_T(page * 2),
                                             flags, DSX::PAGE_READWRITE))
    defer {
      _ = VirtualFreeEx(process, memory, 0, DSX::MEM_RELEASE)
    }
    var previous: DWORD = 0
    try #require(VirtualProtectEx(process, memory, SIZE_T(page), protections.0,
                                  &previous))
    try #require(VirtualProtectEx(process, memory + page, SIZE_T(page),
                                  protections.1, &previous))
    let identifier = ProcessIdentifier(rawValue: UInt64(GetCurrentProcessId()))
    let raw = UInt64(UInt(bitPattern: memory + page - 1))
    let address = Debuggee.Address(rawValue: raw)
    let bytes: Array<UInt8> = [0x90, 0x90]
    var count = 0
    try WindowsMemory.write(identifier, address: address, bytes: bytes.span,
                            count: &count)
    #expect(count == 2)
    var region = MEMORY_BASIC_INFORMATION()
    let size = SIZE_T(MemoryLayout<MEMORY_BASIC_INFORMATION>.size)
    try #require(VirtualQueryEx(process, memory, &region, size) == size)
    #expect(region.Protect == protections.0)
    try #require(VirtualQueryEx(process, memory + page, &region, size) == size)
    #expect(region.Protect == protections.1)
    let written = (memory + page - 1).assumingMemoryBound(to: UInt8.self)
    #expect(written[0] == bytes[0] && written[1] == bytes[1])
  }
}
#endif
