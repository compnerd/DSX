// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct ELFModuleTests {
  @Test(arguments: [false, true], [false, true])
  internal func extent(_ wide: Bool, _ little: Bool) throws {
    let stride = wide ? 56 : 32
    let width = wide ? 8 : 4
    var bytes = Array<UInt8>(repeating: 0, count: 64 + stride * 2)
    bytes.replaceSubrange(0 ..< 6, with: [
      0x7f, 0x45, 0x4c, 0x46, wide ? 2 : 1, little ? 1 : 2,
    ])
    let fields = [
      (wide ? 32 : 28, width, UInt64(64)),
      (wide ? 54 : 42, 2, UInt64(stride)),
      (wide ? 56 : 44, 2, UInt64(2)),
      (64, 4, UInt64(1)),
      (64 + stride, 4, UInt64(1)),
      (64 + (wide ? 16 : 8), width, UInt64(0x400000)),
      (64 + (wide ? 40 : 20), width, UInt64(0x2000)),
      (64 + stride + (wide ? 16 : 8), width, UInt64(0x600000)),
      (64 + stride + (wide ? 40 : 20), width, UInt64(0x1234)),
    ]
    for (offset, count, value) in fields {
      store(value, at: offset, count: count, in: &bytes)
      if little == false {
        bytes[offset ..< (offset + count)].reverse()
      }
    }
    guard let module = try ELFModule(bytes.span) else {
      Issue.record("ELF header was rejected")
      return
    }
    #expect(try module.extent == 0x400000 ..< 0x601234)
  }

  @Test(arguments: [Array<UInt8>(), [0x7f], [0x7f, 0x45, 0x4c],
                    [0x4d, 0x5a, 0, 0],
  ])
  internal func rejected(_ bytes: Array<UInt8>) throws {
    if let _ = try ELFModule(bytes.span) {
      Issue.record("non-ELF data was accepted")
    }
  }

  @Test(arguments: [(4, 2, 1), (5, 2, 1), (63, 2, 1),
                    (64, 0, 1), (64, 3, 1), (64, 2, 0), (64, 2, 3),
  ])
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
    bytes.replaceSubrange(0 ..< 6, with: [
      0x7f, 0x45, 0x4c, 0x46, wide ? 2 : 1, little ? 1 : 2,
    ])
    bytes[little ? 18 : 19] = wide ? 62 : 3
    guard let module = try ELFModule(bytes.span) else {
      Issue.record("ELF header was rejected")
      return
    }
    #expect(try module.architecture == (wide ? "x86_64" : "i386"))
    let checksum = try String(checksum: bytes.span)
    #expect(try module.identifier == checksum)
    #expect(throws: Debuggee.Error.process) {
      _ = try module.extent
    }
    #expect(throws: Debuggee.Error.process) {
      _ = try module.bias(at: 0)
    }
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

  @Test(arguments: [false, true], [false, true])
  internal func relocation(_ wide: Bool, _ little: Bool) throws {
    var bytes = Array<UInt8>(repeating: 0, count: 128)
    bytes.replaceSubrange(0 ..< 6, with: [
      0x7f, 0x45, 0x4c, 0x46, wide ? 2 : 1, little ? 1 : 2,
    ])
    let width = wide ? 8 : 4
    store(64, at: wide ? 32 : 28, count: width, in: &bytes)
    store(wide ? 56 : 32, at: wide ? 54 : 42, count: 2, in: &bytes)
    store(1, at: wide ? 56 : 44, count: 2, in: &bytes)
    store(1, at: 64, count: 4, in: &bytes)
    store(0x400000, at: 64 + (wide ? 16 : 8), count: width, in: &bytes)
    store(128, at: 64 + (wide ? 32 : 16), count: width, in: &bytes)
    if little == false {
      let fields = [
        (wide ? 32 : 28, width),
        (wide ? 54 : 42, 2),
        (wide ? 56 : 44, 2),
        (64, 4),
        (64 + (wide ? 16 : 8), width),
        (64 + (wide ? 32 : 16), width),
      ]
      for (start, count) in fields {
        bytes[start ..< (start + count)].reverse()
      }
    }
    guard let module = try ELFModule(bytes.span) else {
      Issue.record("ELF header was rejected")
      return
    }
    #expect(try module.bias(at: 0x400040) == 0)
    #expect(try module.bias(at: 0x600040) == 0x200000)
    #expect(throws: Debuggee.Error.process) {
      _ = try module.bias(at: 0x40)
    }
  }

  @Test(arguments: [UInt64(0), 65, UInt64.max])
  internal func relocation(_ size: UInt64) throws {
    var bytes = Array<UInt8>(repeating: 0, count: 128)
    bytes.replaceSubrange(0 ..< 6, with: [0x7f, 0x45, 0x4c, 0x46, 2, 1])
    store(64, at: 32, count: 8, in: &bytes)
    store(56, at: 54, count: 2, in: &bytes)
    store(1, at: 56, count: 2, in: &bytes)
    store(1, at: 64, count: 4, in: &bytes)
    store(size, at: 80, count: 8, in: &bytes)
    store(size == UInt64.max ? 128 : size, at: 96, count: 8, in: &bytes)
    #expect(throws: Debuggee.Error.process) {
      _ = try ELFModule(bytes.span)?.bias(at: 0x400040)
    }
  }

  @Test(arguments: [false, true])
  internal func shifted(_ wide: Bool) throws {
    var bytes = Array<UInt8>(repeating: 0, count: 128)
    bytes.replaceSubrange(0 ..< 6,
                          with: [0x7f, 0x45, 0x4c, 0x46, wide ? 2 : 1, 1])
    let width = wide ? 8 : 4
    store(64, at: wide ? 32 : 28, count: width, in: &bytes)
    store(wide ? 56 : 32, at: wide ? 54 : 42, count: 2, in: &bytes)
    store(1, at: wide ? 56 : 44, count: 2, in: &bytes)
    store(1, at: 64, count: 4, in: &bytes)
    store(32, at: 64 + (wide ? 8 : 4), count: width, in: &bytes)
    store(0x400000, at: 64 + (wide ? 16 : 8), count: width, in: &bytes)
    store(96, at: 64 + (wide ? 32 : 16), count: width, in: &bytes)
    #expect(try ELFModule(bytes.span)?.bias(at: 0x400020) == 0)
    #expect(try ELFModule(bytes.span)?.bias(at: 0x600020) == 0x200000)
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
    var prefixed = bytes
    prefixed.append(contentsOf: [1, 2, 3, 4])
    prefixed.replaceSubrange(143 ..< 148, with: "evil\0".utf8)
    store(8, at: 128, count: 4, in: &prefixed)
    store(24, at: 64 + (wide ? 32 : 16), count: wide ? 8 : 4, in: &prefixed)
    #expect(try ELFModule(prefixed.span)?.identifier
        == String(checksum: prefixed.span))
    bytes[143] = UInt8(ascii: "x")
    #expect(try ELFModule(bytes.span)?.identifier == String(checksum: bytes.span))
    bytes[143] = 0
    for size in 0 ..< 4 {
      store(UInt64(size), at: 132, count: 4, in: &bytes)
      #expect(try ELFModule(bytes.span)?.identifier
          == String(checksum: bytes.span))
    }
    store(4, at: 132, count: 4, in: &bytes)
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

  @Test(arguments: [(3, false, "i386", "i386"),
                    (62, true, "x86_64", "x86_64"),
                    (8, false, "mipsel", "mips"),
                    (8, true, "mips64el", "mips64"),
                    (20, false, "powerpcle", "powerpc"),
                    (21, true, "powerpc64le", "powerpc64"),
                    (40, false, "arm", "armeb"),
                    (183, true, "aarch64", "aarch64_be"),
  ])
  internal func architecture(_ fixture: (UInt16, Bool, String, String)) throws {
    let (machine, wide, little, big) = fixture
    var bytes = Array<UInt8>(repeating: 0, count: 64)
    bytes[0] = 0x7f
    bytes[1] = UInt8(ascii: "E")
    bytes[2] = UInt8(ascii: "L")
    bytes[3] = UInt8(ascii: "F")
    bytes[4] = wide ? 2 : 1
    bytes[5] = 1
    bytes[18] = UInt8(truncatingIfNeeded: machine)
    bytes[19] = UInt8(truncatingIfNeeded: machine >> 8)
    #expect(try ELFModule(bytes.span)?.architecture == little)
    bytes[5] = 2
    bytes.swapAt(18, 19)
    #expect(try ELFModule(bytes.span)?.architecture == big)
  }

  @Test
  internal func empty() throws {
    var bytes = Array<UInt8>(repeating: 0, count: 64)
    bytes.replaceSubrange(0 ..< 6, with: [0x7f, 0x45, 0x4c, 0x46, 2, 1])
    let checksum = try String(checksum: bytes.span)
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

  @Test(arguments: [false, true], [false, true])
  internal func extended(_ wide: Bool, _ little: Bool) throws {
    let count = 0xff02
    let stride = wide ? 64 : 40
    let width = wide ? 8 : 4
    let data = 64 + count * stride
    var bytes = Array<UInt8>(repeating: 0, count: data + 64)
    bytes.replaceSubrange(0 ..< 6, with: [
      0x7f, 0x45, 0x4c, 0x46, wide ? 2 : 1, little ? 1 : 2,
    ])
    func field(_ value: UInt64, at offset: Int, size: Int) {
      for index in 0 ..< size {
        let shift = (little ? index : size - index - 1) * 8
        bytes[offset + index] = UInt8(truncatingIfNeeded: value >> shift)
      }
    }
    field(64, at: wide ? 40 : 32, size: width)
    field(UInt64(stride), at: wide ? 58 : 46, size: 2)
    field(0xffff, at: wide ? 62 : 50, size: 2)
    field(UInt64(count), at: 64 + (wide ? 32 : 20), size: width)
    field(0xff00, at: 64 + (wide ? 40 : 24), size: 4)
    let names = 64 + 0xff00 * stride
    field(3, at: names + 4, size: 4)
    field(UInt64(data), at: names + (wide ? 24 : 16), size: width)
    let strings = Array("\0.gnu_debuglink\0".utf8)
    field(UInt64(strings.count), at: names + (wide ? 32 : 20), size: width)
    bytes.replaceSubrange(data ..< (data + strings.count), with: strings)
    let link = 64 + stride
    field(1, at: link, size: 4)
    field(1, at: link + 4, size: 4)
    field(UInt64(data + 32), at: link + (wide ? 24 : 16), size: width)
    field(8, at: link + (wide ? 32 : 20), size: width)
    bytes[data + 32] = UInt8(ascii: "a")
    field(0x12345678, at: data + 36, size: 4)
    #expect(try ELFModule(bytes.span)?.identifier == "78563412")

    // The same extended table can contain a build-ID note.
    field(7, at: link + 4, size: 4)
    field(20, at: link + (wide ? 32 : 20), size: width)
    field(4, at: data + 32, size: 4)
    field(4, at: data + 36, size: 4)
    field(3, at: data + 40, size: 4)
    bytes.replaceSubrange((data + 44) ..< (data + 52),
                          with: [0x47, 0x4e, 0x55, 0, 1, 2, 3, 4])
    #expect(try ELFModule(bytes.span)?.identifier == "01020304")

    field(UInt64.max, at: 64 + (wide ? 32 : 20), size: width)
    #expect(throws: Debuggee.Error.process) {
      _ = try ELFModule(bytes.span)?.identifier
    }
  }

  @Test(arguments: [false, true])
  internal func truncated(_ wide: Bool) {
    var bytes = Array<UInt8>(repeating: 0, count: 64)
    bytes.replaceSubrange(0 ..< 6,
                          with: [0x7f, 0x45, 0x4c, 0x46, wide ? 2 : 1, 1])
    store(64, at: wide ? 40 : 32, count: wide ? 8 : 4, in: &bytes)
    store(wide ? 64 : 40, at: wide ? 58 : 46, count: 2, in: &bytes)
    #expect(throws: Debuggee.Error.process) {
      _ = try ELFModule(bytes.span)?.identifier
    }
  }

  private func store(_ value: UInt64, at offset: Int, count: Int,
                     in bytes: inout Array<UInt8>) {
    for index in 0 ..< count {
      bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (index * 8))
    }
  }
}
