// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct SpanSlicingTests {
  @Test
  internal func matching() {
    let bytes = Array("prefix.gnu_debuglink\0suffix".utf8)
    let cases: Array<(Int, StaticString, Bool)> = [
      (6, ".gnu_debuglink\0", true), (-1, "prefix", false),
      (Int.max, "prefix", false), (7, ".gnu_debuglink\0", false),
      (bytes.count, "x", false), (bytes.count, "", true),
    ]
    for (offset, value, expected) in cases {
      let matched = bytes.span.matches(at: offset, value: value)
      #expect(matched == expected)
    }
  }

  @Test(arguments: [false, true])
  internal func integer(_ little: Bool) throws {
    let bytes: Array<UInt8> = [0x80, 0xff, 1, 2, 3, 4, 5, 6, 7, 0xfe]
    for length in 1 ... 8 {
      for offset in 0 ... bytes.count - length {
        var expected: UInt64 = 0
        for index in 0 ..< length {
          let position = little ? length - index - 1 : index
          expected = expected << 8 | UInt64(bytes[offset + position])
        }
        let value =
            try bytes.span.integer(at: offset, count: length, little: little)
        #expect(value == expected)
        if little {
          #expect(try bytes.span.integer(at: offset, count: length) == expected)
        }
      }
    }
  }

  @Test(arguments: [(-1, 1), (0, 0), (0, -1), (0, 9), (8, 1),
                    (7, 2), (Int.max, 1), (0, Int.max),
  ])
  internal func integer(_ extent: (Int, Int)) {
    let bytes = Array<UInt8>(repeating: 0, count: 8)
    for little in [false, true] {
      #expect(throws: Debuggee.Error.process) {
        _ = try bytes.span.integer(at: extent.0, count: extent.1,
                                   little: little)
      }
    }
    #expect(throws: Debuggee.Error.process) {
      _ = try bytes.span.integer(at: extent.0, count: extent.1)
    }
  }

  @Test
  internal func relative() throws {
    let bytes: Array<UInt8> = [0, 1, 2, 3, 4, 5, 6, 7]
    let slice = try bytes.span.slice(at: 2, size: 4)
    let entries = try slice.slice(at: 0, count: 2, stride: 2)
    #expect(entries.count == 4)
    #expect(try entries.integer(at: 2, count: 2) == 0x0504)
    #expect(try entries.integer(at: 2, count: 2, little: false) == 0x0405)
    #expect(try bytes.span.slice(at: 8, size: 0).isEmpty)
    let records = try bytes.span.slice(at: 2, count: 3, stride: 2)
    #expect(records.count == 6)
    #expect(records[0] == 2)
    #expect(records[5] == 7)
  }

  @Test(arguments: [(UInt64.max, 1), (1, UInt64.max),
                    (7, 2), (9, 0),
  ] as Array<(UInt64, UInt64)>)
  internal func bounds(_ extent: (UInt64, UInt64)) {
    let bytes = Array<UInt8>(repeating: 0, count: 8)
    #expect(throws: Debuggee.Error.process) {
      _ = try bytes.span.slice(at: extent.0, size: extent.1)
    }
  }

  @Test(arguments: [(UInt64.max, 8), (2, UInt64.max),
                    (2, 0), (2, 5),
  ] as Array<(UInt64, UInt64)>)
  internal func records(_ layout: (UInt64, UInt64)) {
    let bytes = Array<UInt8>(repeating: 0, count: 8)
    #expect(throws: Debuggee.Error.process) {
      _ = try bytes.span.slice(at: 0, count: layout.0, stride: layout.1)
    }
  }

  @Test
  internal func empty() throws {
    let bytes = Array<UInt8>()
    let records = try bytes.span.slice(at: UInt64.max, count: 0, stride: 0)
    #expect(records.count == 0)
    #expect(try bytes.span.slice(at: 0, size: 0).isEmpty)
  }

  @Test(arguments: [UInt64(7), 8, 9, UInt64.max])
  internal func offset(_ offset: UInt64) {
    let bytes = Array<UInt8>(repeating: 0, count: 8)
    #expect(throws: Debuggee.Error.process) {
      _ = try bytes.span.slice(at: offset, count: 1, stride: 2)
    }
  }
}
