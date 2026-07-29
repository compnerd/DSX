// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal let LC_SEGMENT: UInt32 = 0x0001
internal let LC_SEGMENT_64: UInt32 = 0x0019
internal let LC_UUID: UInt32 = 0x001b
internal let LC_BUILD_VERSION: UInt32 = 0x0032
internal let LC_VERSION_MIN_MACOSX: UInt32 = 0x0024
internal let LC_VERSION_MIN_IPHONEOS: UInt32 = 0x0025
internal let LC_VERSION_MIN_TVOS: UInt32 = 0x002f
internal let LC_VERSION_MIN_WATCHOS: UInt32 = 0x0030

internal let PLATFORM_MACOS: UInt32 = 1
internal let PLATFORM_IOS: UInt32 = 2
internal let PLATFORM_TVOS: UInt32 = 3
internal let PLATFORM_WATCHOS: UInt32 = 4
internal let PLATFORM_BRIDGEOS: UInt32 = 5
internal let PLATFORM_MACCATALYST: UInt32 = 6
internal let PLATFORM_IOSSIMULATOR: UInt32 = 7
internal let PLATFORM_TVOSSIMULATOR: UInt32 = 8
internal let PLATFORM_WATCHOSSIMULATOR: UInt32 = 9
internal let PLATFORM_DRIVERKIT: UInt32 = 10

/// Validates a command within the header's declared load-command region.
internal struct MachOLoadCommand {
  internal let type: UInt32
  internal let size: UInt32

  internal init(_ type: UInt32, size: UInt32, remaining: UInt64,
                wide: Bool = true) throws(Debuggee.Error) {
    let minimum: UInt32 = switch type {
    case LC_SEGMENT: 56
    case LC_SEGMENT_64: 72
    case LC_UUID, LC_BUILD_VERSION: 24
    case LC_VERSION_MIN_MACOSX, LC_VERSION_MIN_IPHONEOS,
        LC_VERSION_MIN_TVOS, LC_VERSION_MIN_WATCHOS: 16
    default: 8
    }
    guard size >= minimum, size % (wide ? 8 : 4) == 0,
        UInt64(size) <= remaining else {
      throw .process
    }
    self.type = type
    self.size = size
  }

  internal var platform: UInt32? {
    switch type {
    case LC_VERSION_MIN_MACOSX: PLATFORM_MACOS
    case LC_VERSION_MIN_IPHONEOS: PLATFORM_IOS
    case LC_VERSION_MIN_TVOS: PLATFORM_TVOS
    case LC_VERSION_MIN_WATCHOS: PLATFORM_WATCHOS
    default: nil
    }
  }
}
