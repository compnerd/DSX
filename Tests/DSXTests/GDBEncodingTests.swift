// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

import Testing
@testable import DSX

@Suite
internal struct GDBEncodingTests {
  @Test(arguments: UInt8.min ... UInt8.max)
  internal func hexadecimal(_ value: UInt8) {
    let digits = Array("0123456789abcdef".utf8)
    #expect(value.hexadecimal == digits[Int(value & 0x0f)])
    #expect(UInt8(hex: value.hexadecimal) == value & 0x0f)
  }

  @Test(arguments: [UInt64(0), 9, 10, 99, 100, 0xffff_ffff, UInt64.max])
  internal func encoded(_ value: UInt64) {
    let expected = Array(String(value).utf8.flatMap {
      Array(String($0, radix: 16).utf8)
    })
    for count in 0 ... expected.count {
      withUnsafeTemporaryAllocation(of: UInt8.self, capacity: count) { bytes in
        var writer =
            GDBPacketWriter(OutputSpan(buffer: bytes, initializedCount: 0))
        var failure: GDBHandlerError?
        do throws(GDBHandlerError) {
          try writer.encoded(value)
        } catch {
          failure = error
        }
        // A failed byte encoding must not leave a lone hexadecimal digit.
        let initialized = count / 2 * 2
        #expect(writer.count == initialized)
        let prefix = Array(expected.prefix(initialized))
        #expect(Array(bytes.prefix(initialized)) == prefix)
        if count == expected.count {
          #expect(failure == nil)
        } else {
          #expect(failure == .capacity)
        }
      }
    }
  }
}
