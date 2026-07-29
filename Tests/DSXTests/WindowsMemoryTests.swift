// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsMemoryTests {
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
    #expect(try WindowsMemory.write(identifier, address: address,
                                    bytes: bytes.span) == 2)
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
