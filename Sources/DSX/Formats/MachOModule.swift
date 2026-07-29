// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private let FAT_MAGIC: UInt32 = 0xcafe_babe
private let FAT_CIGAM: UInt32 = 0xbeba_feca
private let FAT_MAGIC_64: UInt32 = 0xcafe_babf
private let FAT_CIGAM_64: UInt32 = 0xbfba_feca
private let MH_MAGIC: UInt32 = 0xfeed_face
private let MH_CIGAM: UInt32 = 0xcefa_edfe
private let MH_MAGIC_64: UInt32 = 0xfeed_facf
private let MH_CIGAM_64: UInt32 = 0xcffa_edfe
internal struct MachOModule: ~Escapable {
  private let image: Span<UInt8>
  private let commands: Span<UInt8>
  private let count: Int
  private let little: Bool
  private let wide: Bool
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
    let magic = try image.integer(at: 0, count: 4)
    let layout: (Bool, Bool)? = switch UInt32(magic) {
    case MH_MAGIC: (false, true)
    case MH_CIGAM: (false, false)
    case MH_MAGIC_64: (true, true)
    case MH_CIGAM_64: (true, false)
    default: nil
    }
    guard let (wide, little) = layout else {
      return nil
    }
    let count = try image.integer(at: 16, count: 4, little: little)
    let size = try image.integer(at: 20, count: 4, little: little)
    let commands = try image.slice(at: wide ? 32 : 28, size: size)
    guard count <= size / 8 else {
      throw .process
    }
    self.image = image
    self.commands = commands
    self.count = Int(count)
    self.little = little
    self.wide = wide
    offset = slice.offset
  }

  private static func select(_ bytes: borrowing Span<UInt8>,
                             requested: String?) throws(Debuggee.Error)
      -> (offset: UInt64, size: UInt64) {
    let magic = try bytes.integer(at: 0, count: 4)
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
    let count = try bytes.integer(at: 4, count: 4, little: little)
    guard count > 0 else {
      throw .process
    }
    let stride = wide ? 32 : 20
    let entries = try bytes.slice(at: 8, count: count, stride: UInt64(stride))
    var fallback: (offset: UInt64, size: UInt64)?
    for start in Swift.stride(from: 0, to: entries.count, by: stride) {
      let entry = entries.extracting(start ..< (start + stride))
      let cpu = try entry.integer(at: 0, count: 4, little: little)
      let subtype = try entry.integer(at: 4, count: 4, little: little)
      let offset = try entry.integer(at: 8, count: wide ? 8 : 4, little: little)
      let size = try entry.integer(at: wide ? 16 : 12, count: wide ? 8 : 4,
                                   little: little)
      _ = try bytes.slice(at: offset, size: size)
      let slice = (offset: offset, size: size)
      if fallback == nil {
        fallback = slice
      }
      if let requested,
          let architecture =
              try? String(mach: UInt32(cpu), subtype: UInt32(subtype)),
          architecture.matches(architecture: requested) {
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
        let command = try command(at: cursor)
        if command.type == LC_UUID {
          let uuid = try commands.slice(at: cursor + 8, size: 16)
          return .unique(String(uuid: uuid))
        }
        cursor += UInt64(command.size)
      }
      var checksum = try MD5Checksum()
      try checksum.update(image)
      let digest = try checksum.finish()
      return .digest(String(digest: digest.span))
    }
  }

  internal var architecture: String {
    get throws(Debuggee.Error) {
      let cpu = try image.integer(at: 4, count: 4, little: little)
      let subtype = try image.integer(at: 8, count: 4, little: little)
      return try String(mach: UInt32(cpu), subtype: UInt32(subtype))
    }
  }

  internal var platform: UInt32? {
    get throws(Debuggee.Error) {
      var cursor: UInt64 = 0
      for _ in 0 ..< count {
        let command = try command(at: cursor)
        if command.type == LC_BUILD_VERSION {
          return try UInt32(commands.integer(at: Int(cursor) + 8, count: 4,
                                             little: little))
        }
        if let platform = command.platform {
          return platform
        }
        cursor += UInt64(command.size)
      }
      return nil
    }
  }

  internal var system: String? {
    get throws(Debuggee.Error) {
      try platform.flatMap { String(platform: $0) }
    }
  }

  private func command(at cursor: UInt64) throws(Debuggee.Error)
      -> MachOLoadCommand {
    let entry = try commands.slice(at: cursor, size: 8)
    let size = try UInt32(entry.integer(at: 4, count: 4, little: little))
    let type = try UInt32(entry.integer(at: 0, count: 4, little: little))
    return try MachOLoadCommand(type, size: size,
                                remaining: UInt64(commands.count) - cursor,
                                wide: wide)
  }

}
