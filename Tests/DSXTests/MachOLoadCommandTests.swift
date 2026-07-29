// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct MachOLoadCommandTests {
  @Test(arguments: [(UInt32(0x0019), UInt32(72)), (0x001b, 24), (0x0032, 24),
                    (0x0024, 16), (0x0025, 16), (0x002f, 16), (0x0030, 16),
  ])
  internal func bounds(_ record: (UInt32, UInt32)) throws {
    let command = try MachOLoadCommand(record.0, size: record.1,
                                       remaining: UInt64(record.1))
    #expect(command.type == record.0)
    #expect(command.size == record.1)
    #expect(throws: Debuggee.Error.process) {
      _ = try MachOLoadCommand(record.0, size: 8, remaining: 128)
    }
    #expect(throws: Debuggee.Error.process) {
      _ = try MachOLoadCommand(record.0, size: record.1,
                               remaining: UInt64(record.1 - 1))
    }
  }

  @Test
  internal func alignment() throws {
    _ = try MachOLoadCommand(0xffff, size: 12, remaining: 12, wide: false)
    #expect(throws: Debuggee.Error.process) {
      _ = try MachOLoadCommand(0xffff, size: 12, remaining: 12)
    }
    #expect(throws: Debuggee.Error.process) {
      _ = try MachOLoadCommand(0xffff, size: 0, remaining: 8)
    }
  }
}
