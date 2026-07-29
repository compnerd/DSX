// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm64)
internal import Testing
@testable internal import DSX

internal struct LinuxARM64WatchpointTests {
  @Test(arguments: [UInt64(0), 0xab00_0000_0000_0000,
                    0x005a_0000_0000_0000, 0xab5a_0000_0000_0000])
  internal func addresses(_ tag: UInt64) throws {
    let mask: UInt64 = 0xffff_0000_0000_0000
    let address = Debuggee.Address(rawValue: tag | 0x1230)
    let site = BreakpointSite(address: address, size: 4,
                              kind: .watchpoint(.write), lifetime: .oneshot)
    let adjusted = try LinuxDebugControl.adjust(site, mask: mask)
    #expect(adjusted.address.rawValue == 0x1230)
    #expect(adjusted.size == 4)
    #expect(adjusted.kind == site.kind)
    #expect(adjusted.lifetime == site.lifetime)
    let encoded = try ARM64BreakpointControl(adjusted)
    #expect(encoded.contains((tag | 0x1233) & ~mask))
    #expect(encoded.contains((tag | 0x1234) & ~mask) == false)
  }

  @Test
  internal func alignment() throws {
    let mask: UInt64 = 0xff00_0000_0000_0000
    let address = Debuggee.Address(rawValue: 0xab00_0000_0000_1231)
    let site =
        BreakpointSite(address: address, size: 2, kind: .watchpoint(.write))
    let adjusted = try LinuxDebugControl.adjust(site, mask: mask)
    #expect(adjusted.address.rawValue == 0x1230)
    #expect(adjusted.size == 4)
    let boundary = Debuggee.Address(rawValue: 0xab00_0000_0000_1237)
    let crossing =
        BreakpointSite(address: boundary, size: 2, kind: .watchpoint(.write))
    #expect(throws: Debuggee.Error.breakpoint) {
      try LinuxDebugControl.adjust(crossing, mask: mask)
    }
  }

  @Test
  internal func instructions() throws {
    let address = Debuggee.Address(rawValue: 0xab00_0000_0000_1230)
    let site = BreakpointSite(address: address, size: 4, kind: .hardware)
    let adjusted =
        try LinuxDebugControl.adjust(site, mask: 0xffff_0000_0000_0000)
    #expect(adjusted == site)
  }
}
#endif
