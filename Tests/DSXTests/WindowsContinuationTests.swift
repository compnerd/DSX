// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows) && arch(arm64)
internal import Testing
internal import WinSDK
@testable internal import DSX

@Suite
internal struct WindowsContinuationTests {
  @Test
  internal func preservation() throws {
    var control = WindowsDebugControl()
    control.handle = GetCurrentProcess()
    var saved = CONTEXT()
    saved.ContextFlags = DSX::CONTEXT_ALL
    saved.Pc = 0x1234
    saved.X0 = 0x5678
    saved.Cpsr = 0x0202
    saved.Wvr.0 = 0x1000
    saved.Wcr.0 = 0x0001
    let original = withUnsafeBytes(of: saved) { Array($0) }
    var source = CONTEXT()
    try withUnsafeMutablePointer(to: &saved) { pointer throws(Debuggee.Error) in
      source.X0 = UInt64(UInt(bitPattern: pointer))
      try control.preserve(source)
    }
    let mask = DSX::CONTEXT_DEBUG_REGISTERS ^ DSX::CONTEXT_ARM64
    #expect(saved.ContextFlags == DSX::CONTEXT_ALL & ~mask)
    let start =
        try #require(MemoryLayout<CONTEXT>.offset(of: \CONTEXT.ContextFlags))
    let end = start + MemoryLayout<DWORD>.size
    withUnsafeBytes(of: saved) { bytes in
      #expect(Array(bytes[..<start]) == Array(original[..<start]))
      #expect(Array(bytes[end...]) == Array(original[end...]))
    }
    saved.ContextFlags = DSX::CONTEXT_CONTROL
    try withUnsafeMutablePointer(to: &saved) { pointer throws(Debuggee.Error) in
      source.X0 = UInt64(UInt(bitPattern: pointer))
      try control.preserve(source)
    }
    #expect(saved.ContextFlags == DSX::CONTEXT_CONTROL)
    source.step()
    try withUnsafeMutablePointer(to: &saved) { pointer throws(Debuggee.Error) in
      source.X0 = UInt64(UInt(bitPattern: pointer))
      try control.preserve(source)
    }
    #expect(saved.Cpsr == 0x0202 | SPSR.SS)
    #expect(saved.ContextFlags == DSX::CONTEXT_CONTROL)
    source.X0 = 1
    #expect(throws: Debuggee.Error.self) {
      try control.preserve(source)
    }
  }
}
#endif
