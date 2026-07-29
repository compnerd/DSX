// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal import Testing
@testable internal import DSX

@Suite
internal struct MachOModuleTests {
  @Test
  internal func commands() {
    var bytes = image(0x0100_000c, subtype: 0, identifier: 0x10)
    store(8, at: 20, into: &bytes)
    do {
      _ = try MachOModule(bytes.span)?.identity
      Issue.record("command extending beyond sizeofcmds was accepted")
    } catch {}
  }

  @Test(arguments: [UInt64.max, UInt64(Int.max), UInt64(UInt32.max)])
  internal func bounds(_ offset: UInt64) {
    var bytes = Array<UInt8>(repeating: 0, count: 40)
    store(0xbfba_feca, at: 0, into: &bytes)
    store(1, at: 4, little: false, into: &bytes)
    let high = UInt32(truncatingIfNeeded: offset >> 32)
    let low = UInt32(truncatingIfNeeded: offset)
    store(high, at: 16, little: false, into: &bytes)
    store(low, at: 20, little: false, into: &bytes)
    store(56, at: 28, little: false, into: &bytes)
    do {
      _ = try MachOModule(bytes.span)?.identity
      Issue.record("out-of-bounds Mach-O slice was accepted")
    } catch {}
  }

  @Test
  internal func count() {
    var bytes = Array<UInt8>(repeating: 0, count: 8)
    store(0xbeba_feca, at: 0, into: &bytes)
    store(UInt32.max, at: 4, into: &bytes)
    do {
      _ = try MachOModule(bytes.span, requested: nil)
      Issue.record("out-of-bounds fat architecture records were accepted")
    } catch {}
  }

  @Test
  internal func thin() throws {
    let bytes = image(0x0100_000c, subtype: 0, identifier: 0x10)
    let module = try MachOModule(bytes.span, requested: "arm64")
    #expect(module?.offset == 0)
    #expect(module?.size == UInt64(bytes.count))
    let architecture = try module?.architecture
    #expect(architecture == "arm64")
    let identity = try module?.identity
    guard case .unique(let value)? = identity else {
      Issue.record("Mach-O UUID must be a unique module identity")
      return
    }
    #expect(value == "10111213-1415-1617-1819-1A1B1C1D1E1F")
  }

  @Test
  internal func universal() throws {
    let native = image(0x0100_000c, subtype: 0, identifier: 0x10)
    let enhanced = image(0x0100_000c, subtype: 2, identifier: 0x20)
    var bytes = Array<UInt8>(repeating: 0, count: 0x100)
    store(UInt32(0xbeba_feca), at: 0, into: &bytes)
    store(2, at: 4, little: false, into: &bytes)
    entry(0x0100_000c, subtype: 0, offset: 0x80, size: UInt32(native.count),
          at: 8, into: &bytes)
    entry(0x0100_000c, subtype: 2, offset: 0xc0, size: UInt32(enhanced.count),
          at: 28, into: &bytes)
    bytes.replaceSubrange(0x80 ..< 0x80 + native.count, with: native)
    bytes.replaceSubrange(0xc0 ..< 0xc0 + enhanced.count, with: enhanced)

    let module = try MachOModule(bytes.span, requested: "arm64e")
    #expect(module?.offset == 0xc0)
    #expect(module?.size == UInt64(enhanced.count))
    let architecture = try module?.architecture
    #expect(architecture == "arm64e")
    let identity = try module?.identity
    guard case .unique(let value)? = identity else {
      Issue.record("Mach-O UUID must be a unique module identity")
      return
    }
    #expect(value == "20212223-2425-2627-2829-2A2B2C2D2E2F")
    var malformed = bytes
    store(13, at: 4, little: false, into: &malformed)
    #expect(throws: Debuggee.Error.process) {
      _ = try MachOModule(malformed.span, requested: "arm64")
    }
  }

  @Test(arguments: [false, true])
  internal func digest(_ little: Bool) throws {
    var thin = image(0x0100_000c, subtype: 0, identifier: 0x10)
    store(0, at: 16, into: &thin)
    store(0, at: 20, into: &thin)
    let identity = try MachOModule(thin.span)?.identity
    guard case .digest(let expected)? = identity else {
      Issue.record("Mach-O without a UUID must use a digest")
      return
    }
    var bytes = Array<UInt8>(repeating: 0, count: 0x80)
    store(little ? 0xcafe_babf : 0xbfba_feca, at: 0, into: &bytes)
    store(1, at: 4, little: little, into: &bytes)
    store(0x0100_000c, at: 8, little: little, into: &bytes)
    store(0x40, at: little ? 16 : 20, little: little, into: &bytes)
    store(UInt32(thin.count), at: little ? 24 : 28, little: little,
          into: &bytes)
    bytes.replaceSubrange(0x40 ..< 0x40 + thin.count, with: thin)
    let module = try MachOModule(bytes.span, requested: "arm64")
    #expect(module?.offset == 0x40)
    #expect(module?.size == UInt64(thin.count))
    guard case .digest(let actual)? = try module?.identity else {
      Issue.record("fat Mach-O without a UUID must use a digest")
      return
    }
    #expect(actual == expected)
  }
}

private func image(_ cpu: CInt, subtype: CInt,
                   identifier: UInt8) -> Array<UInt8> {
  var bytes = Array<UInt8>(repeating: 0, count: 56)
  store(UInt32(0xfeed_facf), at: 0, into: &bytes)
  store(UInt32(bitPattern: cpu), at: 4, into: &bytes)
  store(UInt32(bitPattern: subtype), at: 8, into: &bytes)
  store(1, at: 16, into: &bytes)
  store(24, at: 20, into: &bytes)
  store(UInt32(0x001b), at: 32, into: &bytes)
  store(24, at: 36, into: &bytes)
  for index in 0 ..< 16 {
    bytes[40 + index] = identifier + UInt8(index)
  }
  return bytes
}

private func entry(_ cpu: CInt, subtype: CInt, offset: UInt32, size: UInt32,
                   at index: Int, into bytes: inout Array<UInt8>) {
  store(UInt32(bitPattern: cpu), at: index, little: false, into: &bytes)
  store(UInt32(bitPattern: subtype), at: index + 4, little: false, into: &bytes)
  store(offset, at: index + 8, little: false, into: &bytes)
  store(size, at: index + 12, little: false, into: &bytes)
}

private func store(_ value: UInt32, at offset: Int, little: Bool = true,
                   into bytes: inout Array<UInt8>) {
  for index in 0 ..< 4 {
    let byte = little ? index : 3 - index
    bytes[offset + index] = UInt8(truncatingIfNeeded: value >> (byte * 8))
  }
}
