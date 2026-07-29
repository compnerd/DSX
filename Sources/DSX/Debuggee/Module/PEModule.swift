// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private let kDOSHeaderPointer = 0x3c

private enum PEHeader {
  internal static let size = 24
  internal static let signature: UInt64 = 0x0000_4550
  internal static let Machine = 4
  internal static let NumberOfSections = 6
  internal static let SizeOfOptionalHeader = 20
}

private enum PE32 {
  internal static let magic: UInt64 = 0x010b
  internal static let ImageBase = 28
  internal static let DataDirectory = 96
  internal static let NumberOfRvaAndSizes = 92
}

private enum PE32Plus {
  internal static let magic: UInt64 = 0x020b
  internal static let ImageBase = 24
  internal static let DataDirectory = 112
  internal static let NumberOfRvaAndSizes = 108
}

private enum DataDirectory {
  internal static let size = 8
  internal static let debug = 6
  internal static let VirtualAddress = 0
  internal static let Size = 4
}

private enum DebugDirectory {
  internal static let size = 28
  internal static let type = 12
  internal static let SizeOfData = 16
  internal static let PointerToRawData = 24
}

private enum SectionHeader {
  internal static let size = 40
  internal static let VirtualAddress = 12
  internal static let SizeOfRawData = 16
  internal static let PointerToRawData = 20
}

private enum CodeView {
  internal static let type: UInt64 = 2
  internal static let size = 24
  internal static let Age = 20
}

private enum Machine {
  internal static let ARM: UInt64 = 0x01c0
  internal static let ARM64: UInt64 = 0xaa64
  internal static let I386: UInt64 = 0x014c
  internal static let AMD64: UInt64 = 0x8664
}

internal struct PEModule: ~Escapable {
  private let bytes: Span<UInt8>
  private let header: Span<UInt8>
  private let offset: UInt64

  @_lifetime(copy bytes)
  internal init?(_ bytes: consuming Span<UInt8>) throws(Debuggee.Error) {
    guard bytes.count >= 2,
        bytes[0] == UInt8(ascii: "M"), bytes[1] == UInt8(ascii: "Z") else {
      return nil
    }
    let offset = try integer(bytes, at: kDOSHeaderPointer, count: 4)
    let header = try bytes.slice(at: offset, size: UInt64(PEHeader.size))
    guard try integer(header, at: 0, count: 4) == PEHeader.signature else {
      throw .process
    }
    self.offset = offset + UInt64(PEHeader.size)
    self.header = header
    self.bytes = consume bytes
  }

  internal var identifier: String {
    get throws(Debuggee.Error) {
      if let identifier = try codeview() {
        identifier
      } else {
        try ModuleIdentifier.checksum(bytes)
      }
    }
  }

  internal var base: UInt64 {
    get throws(Debuggee.Error) {
      let optional = try optional
      return switch try integer(optional, at: 0, count: 2) {
      case PE32.magic: try integer(optional, at: PE32.ImageBase, count: 4)
      case PE32Plus.magic:
        try integer(optional, at: PE32Plus.ImageBase, count: 8)
      default: throw .process
      }
    }
  }

  internal var architecture: String {
    get throws(Debuggee.Error) {
      let machine = try integer(header, at: PEHeader.Machine, count: 2)
      return try PEModule.architecture(machine)
    }
  }

  internal static func architecture(_ machine: UInt64) throws(Debuggee.Error)
      -> String {
    switch machine {
    case Machine.ARM: "arm"
    case Machine.ARM64: "arm64"
    case Machine.I386: "i386"
    case Machine.AMD64: "x86_64"
    default: throw .process
    }
  }

  private var optional: Span<UInt8> {
    @_lifetime(copy self)
    get throws(Debuggee.Error) {
      let length =
          try integer(header, at: PEHeader.SizeOfOptionalHeader, count: 2)
      guard length >= 2 else {
        throw .process
      }
      return try bytes.slice(at: offset, size: length)
    }
  }

  private func codeview() throws(Debuggee.Error) -> String? {
    let optional = try optional
    let (directories, number) = switch try integer(optional, at: 0, count: 2) {
    case PE32.magic: (PE32.DataDirectory, PE32.NumberOfRvaAndSizes)
    case PE32Plus.magic: (PE32Plus.DataDirectory, PE32Plus.NumberOfRvaAndSizes)
    default: throw .process
    }
    let debug = directories + DataDirectory.debug * DataDirectory.size
    guard optional.count >= debug + DataDirectory.size else {
      return nil
    }
    let available = try integer(optional, at: number, count: 4)
    guard available > DataDirectory.debug else {
      return nil
    }
    let address = try integer(optional,
                              at: debug + DataDirectory.VirtualAddress,
                              count: 4)
    let size = try integer(optional, at: debug + DataDirectory.Size, count: 4)
    let count = try integer(header, at: PEHeader.NumberOfSections, count: 2)
    let sections = try bytes.slice(at: offset + UInt64(optional.count),
                                   count: count,
                                   stride: UInt64(SectionHeader.size))
    guard address > 0, size >= UInt64(DebugDirectory.size),
        let offset = try position(address, sections: sections) else {
      return nil
    }
    let entries = try bytes.slice(at: offset, size: size)
    for index in 0 ..< entries.count / DebugDirectory.size {
      let start = index * DebugDirectory.size
      let entry = entries.extracting(start ..< (start + DebugDirectory.size))
      let type = try integer(entry, at: DebugDirectory.type, count: 4)
      if type == CodeView.type {
        let count = try integer(entry, at: DebugDirectory.SizeOfData, count: 4)
        let position =
            try integer(entry, at: DebugDirectory.PointerToRawData, count: 4)
        if let identifier = try record(bytes.slice(at: position, size: count)) {
          return identifier
        }
      }
    }
    return nil
  }
}

private func position(_ address: UInt64, sections: borrowing Span<UInt8>)
    throws(Debuggee.Error) -> UInt64? {
  for start in stride(from: 0, to: sections.count, by: SectionHeader.size) {
    let entry = sections.extracting(start ..< (start + SectionHeader.size))
    let virtual = try integer(entry, at: SectionHeader.VirtualAddress, count: 4)
    let size = try integer(entry, at: SectionHeader.SizeOfRawData, count: 4)
    let raw = try integer(entry, at: SectionHeader.PointerToRawData, count: 4)
    guard address >= virtual, address - virtual < size else {
      continue
    }
    return raw + address - virtual
  }
  return nil
}

private func record(_ bytes: borrowing Span<UInt8>) throws(Debuggee.Error)
    -> String? {
  guard bytes.count >= CodeView.size else {
    throw .process
  }
  guard bytes[0] == UInt8(ascii: "R"),
      bytes[1] == UInt8(ascii: "S"),
      bytes[2] == UInt8(ascii: "D"),
      bytes[3] == UInt8(ascii: "S") else {
    return nil
  }
  var identifier = String()
  identifier.reserveCapacity(40)
  let Data1 = 4 ..< 8
  let Data2 = 8 ..< 10
  let Data3 = 10 ..< 12
  for field in [Data1, Data2, Data3] {
    for index in field.reversed() {
      ModuleIdentifier.append(bytes[index], to: &identifier)
    }
  }
  for index in 12 ..< 20 {
    ModuleIdentifier.append(bytes[index], to: &identifier)
  }
  let age = try integer(bytes, at: CodeView.Age, count: 4)
  if age > 0 {
    for index in (CodeView.Age ..< CodeView.size).reversed() {
      ModuleIdentifier.append(bytes[index], to: &identifier)
    }
  }
  return identifier
}
