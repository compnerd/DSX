// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
internal import MachO

@_transparent
internal var LC_BUILD_VERSION: UInt32 {
  UInt32(bitPattern: MachO.LC_BUILD_VERSION)
}

@_transparent
internal var LC_VERSION_MIN_MACOSX: UInt32 {
  UInt32(bitPattern: MachO.LC_VERSION_MIN_MACOSX)
}

@_transparent
internal var LC_VERSION_MIN_IPHONEOS: UInt32 {
  UInt32(bitPattern: MachO.LC_VERSION_MIN_IPHONEOS)
}

@_transparent
internal var LC_VERSION_MIN_TVOS: UInt32 {
  UInt32(bitPattern: MachO.LC_VERSION_MIN_TVOS)
}

@_transparent
internal var LC_VERSION_MIN_WATCHOS: UInt32 {
  UInt32(bitPattern: MachO.LC_VERSION_MIN_WATCHOS)
}

@_transparent
internal var PLATFORM_MACOS: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_MACOS)
}

@_transparent
internal var PLATFORM_IOS: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_IOS)
}

@_transparent
internal var PLATFORM_TVOS: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_TVOS)
}

@_transparent
internal var PLATFORM_WATCHOS: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_WATCHOS)
}

@_transparent
internal var PLATFORM_BRIDGEOS: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_BRIDGEOS)
}

@_transparent
internal var PLATFORM_MACCATALYST: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_MACCATALYST)
}

@_transparent
internal var PLATFORM_IOSSIMULATOR: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_IOSSIMULATOR)
}

@_transparent
internal var PLATFORM_TVOSSIMULATOR: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_TVOSSIMULATOR)
}

@_transparent
internal var PLATFORM_WATCHOSSIMULATOR: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_WATCHOSSIMULATOR)
}

@_transparent
internal var PLATFORM_DRIVERKIT: UInt32 {
  UInt32(bitPattern: MachO.PLATFORM_DRIVERKIT)
}

#endif
