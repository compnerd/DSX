// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private let CPU_TYPE_ARM: UInt32 = 0x0000_000c
private let CPU_TYPE_ARM64: UInt32 = 0x0100_000c
private let CPU_TYPE_X86: UInt32 = 0x0000_0007
private let CPU_TYPE_X86_64: UInt32 = 0x0100_0007
private let CPU_SUBTYPE_ARM64E: UInt32 = 0x0002
private let CPU_SUBTYPE_MASK: UInt32 = 0xff00_0000

extension String {
  internal init?(platform: UInt32) {
    switch platform {
    case PLATFORM_MACOS: self = "macosx"
    case PLATFORM_IOS: self = "ios"
    case PLATFORM_TVOS: self = "tvos"
    case PLATFORM_WATCHOS: self = "watchos"
    case PLATFORM_BRIDGEOS: self = "bridgeos"
    case PLATFORM_MACCATALYST: self = "maccatalyst"
    case PLATFORM_IOSSIMULATOR: self = "iossimulator"
    case PLATFORM_TVOSSIMULATOR: self = "tvossimulator"
    case PLATFORM_WATCHOSSIMULATOR: self = "watchossimulator"
    case PLATFORM_DRIVERKIT: self = "driverkit"
    default: return nil
    }
  }

  internal init(mach cpu: UInt32, subtype: UInt32) throws(Debuggee.Error) {
    self = switch cpu {
    case CPU_TYPE_ARM: "arm"
    case CPU_TYPE_ARM64:
      subtype & ~CPU_SUBTYPE_MASK == CPU_SUBTYPE_ARM64E ? "arm64e" : "arm64"
    case CPU_TYPE_X86: "i386"
    case CPU_TYPE_X86_64: "x86_64"
    default: throw .process
    }
  }
}
