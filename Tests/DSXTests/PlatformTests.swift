// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct PlatformTests {
  @Test
  internal func identity() {
    #expect(Host.system.description.isEmpty == false)
    #expect(ABI.machine.description.isEmpty == false)
#if os(Android)
    #expect(Host.platform.description == "linux-android")
#else
    #expect(Host.platform.description == Host.system.description)
#endif
  }

  @Test
  internal func native() {
    #expect(Host.initialize() == nil)
    #expect(ABI.width == MemoryLayout<UnsafeRawPointer>.size * 8)
    #expect(ABI.endian == .little)
    #expect(MemoryLayout<Host>.size == 0)
#if os(anyAppleOS)
    #expect((Host.metadata.addressing ?? 0) > 0)
#else
    #expect(Host.metadata.addressing == nil)
#endif
  }

#if (os(Android) || os(Linux)) && arch(arm64)
  @Test
  internal func registers() {
    #expect(MemoryLayout<LinuxFloatingRegisters>.size == 32 * 16 + 8)
  }
#endif
}
