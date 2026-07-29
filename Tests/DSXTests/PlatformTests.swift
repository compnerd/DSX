// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

#if os(anyAppleOS)
internal import Darwin
#endif

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
    #expect(ABI.width.bytes == MemoryLayout<UnsafeRawPointer>.size)
    #expect(ABI.endian == .little)
    #expect(MemoryLayout<Host>.size == 0)
#if os(anyAppleOS)
    // The optional sysctl is not available on every Darwin architecture.
    var bits: UInt32 = 0
    var size = MemoryLayout<UInt32>.size
    let addressing: UInt64? =
        if sysctlbyname("machdep.virtual_address_size", &bits, &size, nil,
                        0) == 0, bits > 0 {
          UInt64(bits)
        } else {
          nil
        }
    #expect(Host.metadata.addressing == addressing)
#else
    #expect(Host.metadata.addressing == nil)
#endif
  }

#if os(Android) || os(Linux)
  @Test(arguments: ["6.18.35", "6.18.35-azure", "6.18.35+", "6.18.35."])
  internal func version(_ release: String) {
    #expect(Host.version(release) == "6.18.35")
  }

  @Test(arguments: ["", "unknown", ".6"])
  internal func unversioned(_ release: String) {
    #expect(Host.version(release) == nil)
  }
#endif

#if (os(Android) || os(Linux)) && arch(arm64)
  @Test
  internal func registers() {
    #expect(MemoryLayout<LinuxFloatingRegisters>.size == 32 * 16 + 8)
  }
#endif
}
