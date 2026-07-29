// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension String {
  internal init(pe machine: UInt64) throws(Debuggee.Error) {
    let IMAGE_FILE_MACHINE_ARM: UInt64 = 0x01c0
    let IMAGE_FILE_MACHINE_ARM64: UInt64 = 0xaa64
    let IMAGE_FILE_MACHINE_I386: UInt64 = 0x014c
    let IMAGE_FILE_MACHINE_AMD64: UInt64 = 0x8664
    self = switch machine {
    case IMAGE_FILE_MACHINE_ARM: "arm"
    case IMAGE_FILE_MACHINE_ARM64: "arm64"
    case IMAGE_FILE_MACHINE_I386: "i386"
    case IMAGE_FILE_MACHINE_AMD64: "x86_64"
    default: throw .process
    }
  }
}
