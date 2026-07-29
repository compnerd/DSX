// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsStreamTests {
  @Test
  internal func readiness() throws {
    var reader: HANDLE?
    var writer: HANDLE?
    #expect(CreatePipe(&reader, &writer, nil, 0))
    let input = try #require(reader)
    let output = try #require(writer)
    defer {
      _ = CloseHandle(input)
      _ = CloseHandle(output)
    }
    let handle = WindowsStreamHandle.native(input)
    #expect(try WindowsStreamSystem.wait(handle, timeout: 0,
                                         events: Span()) == .timeout)
    let start = GetTickCount64()
    #expect(try WindowsStreamSystem.wait(handle, timeout: 20,
                                         events: Span()) == .timeout)
    #expect(GetTickCount64() - start >= 20)
    var byte: UInt8 = 42
    var count: DWORD = 0
    #expect(WriteFile(output, &byte, 1, &count, nil))
    #expect(try WindowsStreamSystem.wait(handle, timeout: 0,
                                         events: Span()) == .channel)
    #expect(try WindowsStreamSystem.receive(handle, &byte, 1) == 1)
    #expect(byte == 42)
    #expect(try WindowsStreamSystem.wait(handle, timeout: 0,
                                         events: Span()) == .timeout)
  }

  @Test
  internal func closure() throws {
    var reader: HANDLE?
    var writer: HANDLE?
    #expect(CreatePipe(&reader, &writer, nil, 0))
    let input = try #require(reader)
    let output = try #require(writer)
    defer {
      _ = CloseHandle(input)
    }
    #expect(CloseHandle(output))
    let handle = WindowsStreamHandle.native(input)
    #expect(try WindowsStreamSystem.wait(handle, timeout: 0,
                                         events: Span()) == .channel)
    var byte: UInt8 = 0
    #expect(try WindowsStreamSystem.receive(handle, &byte, 1) == 0)
  }
}
#endif
