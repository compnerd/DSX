// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct PEModuleTests {
  @Test(arguments: [Array<UInt8>(), [0x4d], [0x7f, 0x45, 0x4c, 0x46],
                    [0x64, 0x86]])
  internal func rejected(_ bytes: Array<UInt8>) throws {
    if let _ = try PEModule(bytes.span) {
      Issue.record("non-PE data was accepted")
    }
  }

  @Test(arguments: [2, 63, 64])
  internal func malformed(_ count: Int) {
    var bytes = Array<UInt8>(repeating: 0, count: count)
    bytes[0] = 0x4d
    bytes[1] = 0x5a
    #expect(throws: Debuggee.Error.process) {
      _ = try PEModule(bytes.span)
    }
  }

  @Test(arguments: [UInt64(0), 1, 65535])
  internal func deferred(_ length: UInt64) throws {
    var bytes = image(true)
    store(length, at: 0x54, count: 2, into: &bytes)
    guard let module = try PEModule(bytes.span) else {
      Issue.record("PE header was rejected")
      return
    }
    #expect(try module.architecture == "x86_64")
    #expect(throws: Debuggee.Error.process) {
      _ = try module.identifier
    }
    #expect(throws: Debuggee.Error.process) {
      _ = try module.base
    }
  }

  @Test(arguments: [(UInt64(0x014c), "i386"), (0x8664, "x86_64"),
                    (0x01c0, "arm"), (0xaa64, "arm64")])
  internal func machine(_ fixture: (UInt64, String)) throws {
    #expect(try PEModule.architecture(fixture.0) == fixture.1)
  }

  @Test(arguments: [false, true])
  internal func header(_ wide: Bool) throws {
    let bytes = image(wide)
    guard let module = try PEModule(bytes.span) else {
      Issue.record("PE header was rejected")
      return
    }
    #expect(try module.base == 0x0040_0000)
    #expect(try module.architecture
        == (wide ? "x86_64" : "i386"))
    let checksum = try ModuleIdentifier.checksum(bytes.span)
    #expect(try module.identifier == checksum)
  }

  @Test
  internal func truncated() {
    var bytes = image(true)
    store(UInt64(UInt32.max), at: 0x3c, count: 4, into: &bytes)
    do {
      _ = try PEModule(bytes.span)?.architecture
      Issue.record("out-of-bounds PE header was accepted")
    } catch {}
  }

  @Test
  internal func optional() {
    var bytes = image(true)
    store(2, at: 0x40 + 20, count: 2, into: &bytes)
    do {
      _ = try PEModule(bytes.span)?.base
      Issue.record("image base outside the optional header was accepted")
    } catch {}
  }

  @Test(arguments: [false, true],
        [UInt64(0), 1, 0x0102_0304, UInt64(UInt32.max)])
  internal func codeview(_ wide: Bool, _ age: UInt64) throws {
    var bytes = image(wide)
    let number = 0x58 + (wide ? 108 : 92)
    store(7, at: number, count: 4, into: &bytes)
    let directory = 0x58 + (wide ? 112 : 96) + 6 * 8
    store(0x1000, at: directory, count: 4, into: &bytes)
    store(28, at: directory + 4, count: 4, into: &bytes)
    store(1, at: 0x40 + 6, count: 2, into: &bytes)
    let section = 0x58 + (wide ? 240 : 224)
    store(0x1000, at: section + 12, count: 4, into: &bytes)
    store(128, at: section + 16, count: 4, into: &bytes)
    store(384, at: section + 20, count: 4, into: &bytes)
    store(2, at: 384 + 12, count: 4, into: &bytes)
    store(24, at: 384 + 16, count: 4, into: &bytes)
    store(416, at: 384 + 24, count: 4, into: &bytes)
    store(0x5344_5352, at: 416, count: 4, into: &bytes)
    for index in 0 ..< 16 {
      bytes[420 + index] = UInt8(index)
    }
    store(age, at: 436, count: 4, into: &bytes)
    let suffix = String(age, radix: 16, uppercase: true)
    let padding = String(repeating: "0", count: 8 - suffix.count)
    let expected = "030201000504070608090A0B0C0D0E0F" +
        (age == 0 ? "" : padding + suffix)
    #expect(try PEModule(bytes.span)?.identifier == expected)
    store(6, at: number, count: 4, into: &bytes)
    #expect(try PEModule(bytes.span)?.identifier
        == ModuleIdentifier.checksum(bytes.span))
    store(0, at: number, count: 4, into: &bytes)
    #expect(try PEModule(bytes.span)?.identifier
        == ModuleIdentifier.checksum(bytes.span))
    store(7, at: number, count: 4, into: &bytes)
    store(29, at: directory + 4, count: 4, into: &bytes)
    #expect(try PEModule(bytes.span)?.identifier == expected)
    store(129, at: directory + 4, count: 4, into: &bytes)
    #expect(throws: Debuggee.Error.process) {
      _ = try PEModule(bytes.span)?.identifier
    }
    store(28, at: directory + 4, count: 4, into: &bytes)
    store(6, at: 0x40 + 6, count: 2, into: &bytes)
    #expect(throws: Debuggee.Error.process) {
      _ = try PEModule(bytes.span)?.identifier
    }
  }
}

private func image(_ wide: Bool) -> Array<UInt8> {
  var bytes = Array<UInt8>(repeating: 0, count: 512)
  bytes[0] = UInt8(ascii: "M")
  bytes[1] = UInt8(ascii: "Z")
  store(0x40, at: 0x3c, count: 4, into: &bytes)
  store(0x4550, at: 0x40, count: 4, into: &bytes)
  store(wide ? 0x8664 : 0x014c, at: 0x44, count: 2, into: &bytes)
  store(wide ? 240 : 224, at: 0x54, count: 2, into: &bytes)
  store(wide ? 0x020b : 0x010b, at: 0x58, count: 2, into: &bytes)
  store(0x0040_0000, at: 0x58 + (wide ? 24 : 28), count: wide ? 8 : 4,
        into: &bytes)
  return bytes
}

private func store(_ value: UInt64, at offset: Int, count: Int,
                   into bytes: inout Array<UInt8>) {
  for index in 0 ..< count {
    bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8))
  }
}
