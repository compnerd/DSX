// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct MachOModule: ~Escapable {
  private let image: Span<UInt8>
  private let commands: Span<UInt8>
  private let count: Int
  private let little: Bool
  internal let offset: UInt64

  internal var size: UInt64 {
    UInt64(image.count)
  }

  @_lifetime(copy bytes)
  internal init?(_ bytes: consuming Span<UInt8>, requested: String? = nil)
      throws(Debuggee.Error) {
    guard bytes.count >= 4 else {
      return nil
    }
    let slice = try MachOModule.select(bytes, requested: requested)
    let image = try bytes.slice(at: slice.offset, size: slice.size)
    let magic = try integer(image, at: 0, count: 4)
    let layout: (Bool, Bool)? = switch UInt32(magic) {
    case MachOModule.MH_MAGIC: (false, true)
    case MachOModule.MH_CIGAM: (false, false)
    case MachOModule.MH_MAGIC_64: (true, true)
    case MachOModule.MH_CIGAM_64: (true, false)
    default: nil
    }
    guard let (wide, little) = layout else {
      return nil
    }
    let count = try integer(image, at: 16, count: 4, little: little)
    let size = try integer(image, at: 20, count: 4, little: little)
    let commands = try image.slice(at: wide ? 32 : 28, size: size)
    guard count <= size / 8 else {
      throw .process
    }
    self.image = image
    self.commands = commands
    self.count = Int(count)
    self.little = little
    offset = slice.offset
  }

  private static let FAT_MAGIC: UInt32 = 0xcafe_babe
  private static let FAT_CIGAM: UInt32 = 0xbeba_feca
  private static let FAT_MAGIC_64: UInt32 = 0xcafe_babf
  private static let FAT_CIGAM_64: UInt32 = 0xbfba_feca
  private static let MH_MAGIC: UInt32 = 0xfeed_face
  private static let MH_CIGAM: UInt32 = 0xcefa_edfe
  private static let MH_MAGIC_64: UInt32 = 0xfeed_facf
  private static let MH_CIGAM_64: UInt32 = 0xcffa_edfe
  private static let LC_UUID: UInt32 = 0x001b
  private static let CPU_TYPE_ARM: UInt32 = 0x0000_000c
  private static let CPU_TYPE_ARM64: UInt32 = 0x0100_000c
  private static let CPU_TYPE_X86: UInt32 = 0x0000_0007
  private static let CPU_TYPE_X86_64: UInt32 = 0x0100_0007
  private static let CPU_SUBTYPE_ARM64E: UInt32 = 0x0002
  private static let CPU_SUBTYPE_MASK: UInt32 = 0xff00_0000

  private static func select(_ bytes: borrowing Span<UInt8>,
                             requested: String?) throws(Debuggee.Error)
      -> (offset: UInt64, size: UInt64) {
    let magic = try integer(bytes, at: 0, count: 4)
    let layout: (Bool, Bool)? = switch UInt32(magic) {
    case FAT_MAGIC: (false, true)
    case FAT_CIGAM: (false, false)
    case FAT_MAGIC_64: (true, true)
    case FAT_CIGAM_64: (true, false)
    default: nil
    }
    guard let (wide, little) = layout else {
      return (offset: 0, size: UInt64(bytes.count))
    }
    let count = try integer(bytes, at: 4, count: 4, little: little)
    guard count > 0 else {
      throw .process
    }
    let stride = wide ? 32 : 20
    let entries = try bytes.slice(at: 8, count: count, stride: UInt64(stride))
    var fallback: (offset: UInt64, size: UInt64)?
    for start in Swift.stride(from: 0, to: entries.count, by: stride) {
      let entry = entries.extracting(start ..< (start + stride))
      let cpu = try integer(entry, at: 0, count: 4, little: little)
      let subtype = try integer(entry, at: 4, count: 4, little: little)
      let offset =
          try integer(entry, at: 8, count: wide ? 8 : 4, little: little)
      let size = try integer(entry, at: wide ? 16 : 12, count: wide ? 8 : 4,
                             little: little)
      _ = try bytes.slice(at: offset, size: size)
      let slice = (offset: offset, size: size)
      if fallback == nil {
        fallback = slice
      }
      if match(UInt32(cpu), subtype: UInt32(subtype), requested: requested) {
        return slice
      }
    }
    guard requested == nil, let fallback else {
      throw .process
    }
    return fallback
  }

  internal var identity: Debuggee.Module.Identity {
    get throws(Debuggee.Error) {
      var cursor: UInt64 = 0
      for _ in 0 ..< count {
        let entry = try commands.slice(at: cursor, size: 8)
        let command = try integer(entry, at: 0, count: 4, little: little)
        let size = try integer(entry, at: 4, count: 4, little: little)
        guard size >= 8 else {
          throw .process
        }
        let contents = try commands.slice(at: cursor, size: size)
        if UInt32(command) == MachOModule.LC_UUID {
          guard size >= 24 else {
            throw .process
          }
          return .unique(MachOModule.unique(contents, at: 8))
        }
        cursor += size
      }
      var checksum = MD5Checksum()
      checksum.update(image)
      return .digest(MachOModule.digest(checksum.finish()))
    }
  }

  internal var architecture: String {
    get throws(Debuggee.Error) {
      let cpu = try integer(image, at: 4, count: 4, little: little)
      let subtype = try integer(image, at: 8, count: 4, little: little)
      return try MachOModule.name(UInt32(cpu), subtype: UInt32(subtype))
    }
  }

  private static func match(_ cpu: UInt32, subtype: UInt32,
                            requested: String?) -> Bool {
    guard let requested else {
      return false
    }
    guard let architecture = try? name(cpu, subtype: subtype) else {
      return false
    }
    return ModuleArchitecture.matches(architecture, requested: requested)
  }

  private static func name(_ cpu: UInt32, subtype: UInt32)
      throws(Debuggee.Error) -> String {
    switch cpu {
    case CPU_TYPE_ARM: "arm"
    case CPU_TYPE_ARM64:
      subtype & ~CPU_SUBTYPE_MASK
          == CPU_SUBTYPE_ARM64E ? "arm64e" : "arm64"
    case CPU_TYPE_X86: "i386"
    case CPU_TYPE_X86_64: "x86_64"
    default: throw .process
    }
  }

  private static func unique(_ bytes: borrowing Span<UInt8>, at offset: Int)
      -> String {
    var value = String()
    value.reserveCapacity(36)
    for index in 0 ..< 16 {
      if index == 4 || index == 6 || index == 8 || index == 10 {
        value.append("-")
      }
      ModuleIdentifier.append(bytes[offset + index], to: &value)
    }
    return value
  }

  private static func digest(_ bytes: borrowing InlineArray<16, UInt8>)
      -> String {
    var value = String()
    value.reserveCapacity(32)
    for index in 0 ..< 16 {
      ModuleIdentifier.append(bytes[index], to: &value)
    }
    return value
  }
}
