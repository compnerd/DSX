// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private enum COFFHeader {
  internal static let size: UInt64 = 20
  internal static let Machine = 0
  internal static let NumberOfSections = 2
  internal static let PointerToSymbolTable = 8
  internal static let NumberOfSymbols = 12
  internal static let SizeOfOptionalHeader = 16
  internal static let SectionSize: UInt64 = 40
  internal static let SymbolSize: UInt64 = 18
}

extension String {
  @inline(__always)
  internal init(coff bytes: borrowing Span<UInt8>) throws(Debuggee.Error) {
    guard UInt64(bytes.count) >= COFFHeader.size else {
      throw .process
    }
    let sections = try bytes.integer(at: COFFHeader.NumberOfSections, count: 2)
    let optional =
        try bytes.integer(at: COFFHeader.SizeOfOptionalHeader, count: 2)
    let size = COFFHeader.size + optional + sections * COFFHeader.SectionSize
    guard size <= UInt64(bytes.count) else {
      throw .process
    }
    let symbols =
        try bytes.integer(at: COFFHeader.PointerToSymbolTable, count: 4)
    let count = try bytes.integer(at: COFFHeader.NumberOfSymbols, count: 4)
    if count > 0 {
      let end = symbols + count * COFFHeader.SymbolSize
      guard symbols > 0, end <= UInt64(bytes.count) else {
        throw .process
      }
    }
    try self.init(pe: bytes.integer(at: COFFHeader.Machine, count: 2))
  }

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
