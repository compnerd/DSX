// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

private let kDOSHeaderPointer = 0x3c

private enum PEHeader {
  internal static let size = 24
  internal static let signature: UInt64 = 0x0000_4550
  internal static let Machine = 4
  internal static let NumberOfSections = 6
  internal static let PointerToSymbolTable = 12
  internal static let NumberOfSymbols = 16
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
  internal static let Name = 0
  internal static let NameSize = 8
  internal static let size = 40
  internal static let VirtualAddress = 12
  internal static let SizeOfRawData = 16
  internal static let PointerToRawData = 20
}

private let kCOFFSymbolSize: UInt64 = 18

private enum CodeView {
  internal static let type: UInt64 = 2
  internal static let size = 24
  internal static let Age = 20
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
    let offset = try bytes.integer(at: kDOSHeaderPointer, count: 4)
    let header = try bytes.slice(at: offset, size: UInt64(PEHeader.size))
    guard try header.integer(at: 0, count: 4) == PEHeader.signature else {
      throw .process
    }
    self.offset = offset + UInt64(PEHeader.size)
    self.header = header
    self.bytes = consume bytes
  }

  internal var identifier: String {
    get throws(Debuggee.Error) {
      if let identifier = try codeview() {
        return identifier
      }
      if let identifier = try debuglink() {
        return identifier
      }
      return try String(checksum: bytes)
    }
  }

  internal var base: UInt64 {
    get throws(Debuggee.Error) {
      let optional = try optional
      return switch try optional.integer(at: 0, count: 2) {
      case PE32.magic: try optional.integer(at: PE32.ImageBase, count: 4)
      case PE32Plus.magic:
        try optional.integer(at: PE32Plus.ImageBase, count: 8)
      default: throw .process
      }
    }
  }

  internal var architecture: String {
    get throws(Debuggee.Error) {
      let machine = try header.integer(at: PEHeader.Machine, count: 2)
      return try String(pe: machine)
    }
  }

  private var optional: Span<UInt8> {
    @_lifetime(copy self)
    get throws(Debuggee.Error) {
      let length =
          try header.integer(at: PEHeader.SizeOfOptionalHeader, count: 2)
      guard length >= 2 else {
        throw .process
      }
      return try bytes.slice(at: offset, size: length)
    }
  }

  private var sections: Span<UInt8> {
    @_lifetime(copy self)
    get throws(Debuggee.Error) {
      let count = try header.integer(at: PEHeader.NumberOfSections, count: 2)
      let length =
          try header.integer(at: PEHeader.SizeOfOptionalHeader, count: 2)
      return try bytes.slice(at: offset + length, count: count,
                             stride: UInt64(SectionHeader.size))
    }
  }

  private func debuglink() throws(Debuggee.Error) -> String? {
    let sections = try sections
    for start in stride(from: 0, to: sections.count, by: SectionHeader.size) {
      let entry = sections.extracting(start ..< (start + SectionHeader.size))
      guard entry[SectionHeader.Name] == UInt8(ascii: "/") else {
        continue
      }
      var end = 1
      while end < SectionHeader.NameSize, entry[end] != 0 {
        end += 1
      }
      guard let name = entry.extracting(1 ..< end).decimal() else {
        continue
      }
      let symbols =
          try header.integer(at: PEHeader.PointerToSymbolTable, count: 4)
      guard symbols > 0 else {
        continue
      }
      let count = try header.integer(at: PEHeader.NumberOfSymbols, count: 4)
      let offset = symbols + count * kCOFFSymbolSize
      let prefix = try bytes.slice(at: offset, size: 4)
      let size = try prefix.integer(at: 0, count: 4)
      let strings = try bytes.slice(at: offset, size: size)
      guard name >= 4, name < size,
          strings.matches(at: Int(name), value: ".gnu_debuglink\0") else {
        continue
      }
      let data = try entry.integer(at: SectionHeader.PointerToRawData, count: 4)
      let length = try entry.integer(at: SectionHeader.SizeOfRawData, count: 4)
      return try String(debuglink: bytes.slice(at: data, size: length))
    }
    return nil
  }

  private func codeview() throws(Debuggee.Error) -> String? {
    let optional = try optional
    let (directories, number) = switch try optional.integer(at: 0, count: 2) {
    case PE32.magic: (PE32.DataDirectory, PE32.NumberOfRvaAndSizes)
    case PE32Plus.magic: (PE32Plus.DataDirectory, PE32Plus.NumberOfRvaAndSizes)
    default: throw .process
    }
    let debug = directories + DataDirectory.debug * DataDirectory.size
    guard optional.count >= debug + DataDirectory.size else {
      return nil
    }
    let available = try optional.integer(at: number, count: 4)
    guard available > DataDirectory.debug else {
      return nil
    }
    let address =
        try optional.integer(at: debug + DataDirectory.VirtualAddress, count: 4)
    let size = try optional.integer(at: debug + DataDirectory.Size, count: 4)
    let offset = try position(rva: address)
    guard address > 0, size >= UInt64(DebugDirectory.size), let offset else {
      return nil
    }
    let entries = try bytes.slice(at: offset, size: size)
    for index in 0 ..< entries.count / DebugDirectory.size {
      let start = index * DebugDirectory.size
      let entry = entries.extracting(start ..< (start + DebugDirectory.size))
      let type = try entry.integer(at: DebugDirectory.type, count: 4)
      if type == CodeView.type {
        let count = try entry.integer(at: DebugDirectory.SizeOfData, count: 4)
        let position =
            try entry.integer(at: DebugDirectory.PointerToRawData, count: 4)
        if let identifier =
            try String(codeview: bytes.slice(at: position, size: count)) {
          return identifier
        }
      }
    }
    return nil
  }
}

extension PEModule {
  private func position(rva address: UInt64) throws(Debuggee.Error) -> UInt64? {
    let sections = try sections
    for start in stride(from: 0, to: sections.count, by: SectionHeader.size) {
      let entry = sections.extracting(start ..< (start + SectionHeader.size))
      let virtual =
          try entry.integer(at: SectionHeader.VirtualAddress, count: 4)
      let size = try entry.integer(at: SectionHeader.SizeOfRawData, count: 4)
      let raw = try entry.integer(at: SectionHeader.PointerToRawData, count: 4)
      guard address >= virtual, address - virtual < size else {
        continue
      }
      return raw + address - virtual
    }
    return nil
  }
}

extension String {
  fileprivate init?(codeview bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
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
        identifier.append(hex: bytes[index])
      }
    }
    for index in 12 ..< 20 {
      identifier.append(hex: bytes[index])
    }
    let age = try bytes.integer(at: CodeView.Age, count: 4)
    if age > 0 {
      for index in (CodeView.Age ..< CodeView.size).reversed() {
        identifier.append(hex: bytes[index])
      }
    }
    self = identifier
  }
}
