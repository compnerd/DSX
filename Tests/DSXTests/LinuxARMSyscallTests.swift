// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && arch(arm)
internal import Testing
@testable internal import DSX

@Suite
internal struct LinuxARMSyscallTests {
  @Test
  internal func breakpoint() throws {
    for size in [2, 4] {
      try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 4) { bytes in
        var output = OutputSpan(buffer: bytes, initializedCount: 0)
        try ABI.breakpoint(size, into: &output)
        let expected: Array<UInt8> = size == 2 ? [0x01, 0xde]
            : [0xf0, 0x01, 0xf0, 0xe7]
        #expect(output.count == expected.count)
        for index in 0 ..< output.count {
          #expect(output.span[index] == expected[index])
        }
      }
    }
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 4) { bytes in
      var output = OutputSpan(buffer: bytes, initializedCount: 0)
      #expect(throws: Debuggee.Error.breakpoint) {
        try ABI.breakpoint(3, into: &output)
      }
      #expect(output.count == 0)
    }
  }

  @Test
  internal func injection() throws {
    for status: UInt32 in [0x10, 0x30, 0xa600_fc30] {
      var registers = LinuxGeneralRegisters()
      registers.values[16] = status
      let arguments: Array<UInt64> = [192, 0, 4096, 3, 0x22, UInt64.max, 0]
      try registers.prepare(arguments.span)
      #expect(registers.values[16] & 0x0700_fc20 == 0x20)
      #expect(registers.values[16] & 0xf000_001f == status & 0xf000_001f)
      #expect(registers.values[7] == 192)
      #expect(registers.values[4] == UInt32.max)
      registers.set(pc: 0x1000)
      #expect(registers.pc == 0x1000)
      var bytes = InlineArray<4, UInt8> { _ in 0 }
      #expect(registers.instruction(into: &bytes) == 2)
      #expect(bytes[0] == 0x00 && bytes[1] == 0xdf)
      #expect(bytes[2] == 0x01 && bytes[3] == 0xde)
    }
  }
}
#endif
