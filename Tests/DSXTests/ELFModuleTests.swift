// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct ELFModuleTests {
  @Test(arguments: [Array<UInt8>(), [0x7f], [0x7f, 0x45, 0x4c],
                    [0x4d, 0x5a, 0, 0]])
  internal func rejected(_ bytes: Array<UInt8>) throws {
    if let _ = try ELFModule(bytes.span) {
      Issue.record("non-ELF data was accepted")
    }
  }

  @Test(arguments: [(4, 2, 1), (5, 2, 1), (63, 2, 1),
                    (64, 0, 1), (64, 3, 1), (64, 2, 0), (64, 2, 3)])
  internal func malformed(_ fixture: (Int, UInt8, UInt8)) {
    let (count, format, order) = fixture
    var bytes = Array<UInt8>(repeating: 0, count: count)
    bytes.replaceSubrange(0 ..< 4, with: [0x7f, 0x45, 0x4c, 0x46])
    if count > 5 {
      bytes[4] = format
      bytes[5] = order
    }
    #expect(throws: Debuggee.Error.process) {
      _ = try ELFModule(bytes.span)
    }
  }

  @Test(arguments: [false, true], [false, true])
  internal func properties(_ wide: Bool, _ little: Bool) throws {
    var bytes = Array<UInt8>(repeating: 0, count: wide ? 64 : 52)
    bytes.replaceSubrange(0 ..< 6,
                          with: [0x7f, 0x45, 0x4c, 0x46,
                                 wide ? 2 : 1, little ? 1 : 2])
    bytes[little ? 18 : 19] = wide ? 62 : 3
    guard let module = try ELFModule(bytes.span) else {
      Issue.record("ELF header was rejected")
      return
    }
    #expect(try module.architecture == (wide ? "x86_64" : "i386"))
    let checksum = try ModuleIdentifier.checksum(bytes.span)
    #expect(try module.identifier == checksum)
  }

  @Test
  internal func deferred() throws {
    var bytes = Array<UInt8>(repeating: 0, count: 64)
    bytes.replaceSubrange(0 ..< 6, with: [0x7f, 0x45, 0x4c, 0x46, 2, 1])
    bytes[18] = 62
    store(UInt64.max, at: 32, count: 8, in: &bytes)
    store(56, at: 54, count: 2, in: &bytes)
    store(1, at: 56, count: 2, in: &bytes)
    guard let module = try ELFModule(bytes.span) else {
      Issue.record("ELF header was rejected")
      return
    }
    #expect(try module.architecture == "x86_64")
    #expect(throws: Debuggee.Error.process) {
      _ = try module.identifier
    }
  }

  @Test(arguments: [UInt64.max, UInt64(Int.max), UInt64(UInt32.max)])
  internal func bounds(_ offset: UInt64) {
    var bytes = Array<UInt8>(repeating: 0, count: 64)
    bytes.replaceSubrange(0 ..< 6, with: [0x7f, 0x45, 0x4c, 0x46, 2, 1])
    store(offset, at: 32, count: 8, in: &bytes)
    store(56, at: 54, count: 2, in: &bytes)
    store(1, at: 56, count: 2, in: &bytes)
    do {
      _ = try ELFModule(bytes.span)?.identifier
      Issue.record("out-of-bounds program header was accepted")
    } catch {}
  }

  @Test(arguments: [false, true])
  internal func notes(_ wide: Bool) throws {
    var bytes = Array<UInt8>(repeating: 0, count: 148)
    bytes.replaceSubrange(0 ..< 6,
                          with: [0x7f, 0x45, 0x4c, 0x46, wide ? 2 : 1, 1])
    store(64, at: wide ? 32 : 28, count: wide ? 8 : 4, in: &bytes)
    store(wide ? 56 : 32, at: wide ? 54 : 42, count: 2, in: &bytes)
    store(1, at: wide ? 56 : 44, count: 2, in: &bytes)
    store(4, at: 64, count: 4, in: &bytes)
    store(128, at: 64 + (wide ? 8 : 4), count: wide ? 8 : 4, in: &bytes)
    store(20, at: 64 + (wide ? 32 : 16), count: wide ? 8 : 4, in: &bytes)
    store(4, at: 128, count: 4, in: &bytes)
    store(4, at: 132, count: 4, in: &bytes)
    store(3, at: 136, count: 4, in: &bytes)
    bytes.replaceSubrange(140 ..< 148, with: [0x47, 0x4e, 0x55, 0, 1, 2, 3, 4])
    #expect(try ELFModule(bytes.span)?.identifier == "01020304")
    store(3, at: wide ? 56 : 44, count: 2, in: &bytes)
    #expect(throws: Debuggee.Error.process) {
      _ = try ELFModule(bytes.span)?.identifier
    }
    store(1, at: wide ? 56 : 44, count: 2, in: &bytes)
    store(UInt64(UInt32.max), at: 128, count: 4, in: &bytes)
    do {
      _ = try ELFModule(bytes.span)?.identifier
      Issue.record("out-of-bounds ELF note was accepted")
    } catch {}
  }

  @Test(arguments: [(3, false, "i386"), (62, true, "x86_64"),
                    (183, true, "aarch64"), (20, false, "powerpc"),
                    (21, true, "powerpc64")])
  internal func architecture(_ fixture: (UInt16, Bool, String)) throws {
    let (machine, wide, expected) = fixture
    var bytes = Array<UInt8>(repeating: 0, count: 64)
    bytes[0] = 0x7f
    bytes[1] = UInt8(ascii: "E")
    bytes[2] = UInt8(ascii: "L")
    bytes[3] = UInt8(ascii: "F")
    bytes[4] = wide ? 2 : 1
    bytes[5] = 1
    bytes[18] = UInt8(truncatingIfNeeded: machine)
    bytes[19] = UInt8(truncatingIfNeeded: machine >> 8)
    #expect(try ELFModule(bytes.span)?.architecture == expected)
  }

  @Test
  internal func empty() throws {
    var bytes = Array<UInt8>(repeating: 0, count: 64)
    bytes.replaceSubrange(0 ..< 6, with: [0x7f, 0x45, 0x4c, 0x46, 2, 1])
    let checksum = try ModuleIdentifier.checksum(bytes.span)
    #expect(try ELFModule(bytes.span)?.identifier == checksum)
  }

  @Test(arguments: [false, true])
  internal func debuglink(_ wide: Bool) throws {
    var bytes = Array<UInt8>(repeating: 0, count: 512)
    bytes[0] = 0x7f
    bytes[1] = UInt8(ascii: "E")
    bytes[2] = UInt8(ascii: "L")
    bytes[3] = UInt8(ascii: "F")
    bytes[4] = wide ? 2 : 1
    bytes[5] = 1

    let width = wide ? 64 : 40
    store(64, at: wide ? 40 : 32, count: wide ? 8 : 4, in: &bytes)
    store(UInt64(width), at: wide ? 58 : 46, count: 2, in: &bytes)
    store(3, at: wide ? 60 : 48, count: 2, in: &bytes)
    store(1, at: wide ? 62 : 50, count: 2, in: &bytes)

    let names = Array("\0.shstrtab\0.gnu_debuglink\0".utf8)
    for index in names.indices {
      bytes[256 + index] = names[index]
    }
    section(1, name: 1, offset: 256, size: names.count, width: width,
            wide: wide, bytes: &bytes)
    section(2, name: 11, offset: 320, size: 16, width: width, wide: wide,
            bytes: &bytes)

    let data = Array("a.out.debug\0".utf8)
    for index in data.indices {
      bytes[320 + index] = data[index]
    }
    bytes[332] = 0x72
    bytes[333] = 0xad
    bytes[334] = 0x2c
    bytes[335] = 0xfc

    #expect(try ELFModule(bytes.span)?.identifier == "72AD2CFC")
  }

  private func section(_ index: Int, name: UInt64, offset: UInt64, size: Int,
                       width: Int, wide: Bool, bytes: inout Array<UInt8>) {
    let start = 64 + index * width
    store(name, at: start, count: 4, in: &bytes)
    store(index == 1 ? 3 : 1, at: start + 4, count: 4, in: &bytes)
    store(offset, at: start + (wide ? 24 : 16), count: wide ? 8 : 4, in: &bytes)
    store(UInt64(size), at: start + (wide ? 32 : 20), count: wide ? 8 : 4,
          in: &bytes)
  }

  private func store(_ value: UInt64, at offset: Int, count: Int,
                     in bytes: inout Array<UInt8>) {
    for index in 0 ..< count {
      bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8))
    }
  }
}
