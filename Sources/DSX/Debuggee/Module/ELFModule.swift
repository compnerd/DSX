// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal let kELF32ProgramHeaderSize = 32
internal let kELF64ProgramHeaderSize = 56

private enum Identification {
  internal static let EI_MAG0 = 0
  internal static let EI_MAG1 = 1
  internal static let EI_MAG2 = 2
  internal static let EI_MAG3 = 3
  internal static let EI_CLASS = 4
  internal static let EI_DATA = 5
  internal static let SELFMAG = 4
  internal static let ELFMAG0: UInt8 = 0x7f
  internal static let ELFCLASS32: UInt8 = 1
  internal static let ELFCLASS64: UInt8 = 2
  internal static let ELFDATA2LSB: UInt8 = 1
  internal static let ELFDATA2MSB: UInt8 = 2
}

private enum Header {
  internal static let e_machine = 18
}

private enum Header32 {
  internal static let size = 52
  internal static let e_phoff = 28
  internal static let e_shoff = 32
  internal static let e_phentsize = 42
  internal static let e_phnum = 44
  internal static let e_shentsize = 46
  internal static let e_shnum = 48
  internal static let e_shstrndx = 50
}

private enum Header64 {
  internal static let size = 64
  internal static let e_phoff = 32
  internal static let e_shoff = 40
  internal static let e_phentsize = 54
  internal static let e_phnum = 56
  internal static let e_shentsize = 58
  internal static let e_shnum = 60
  internal static let e_shstrndx = 62
}

private enum ProgramHeader {
  internal static let p_type = 0
  internal static let PT_NOTE: UInt64 = 4
}

private enum Program32 {
  internal static let p_offset = 4
  internal static let p_filesz = 16
}

private enum Program64 {
  internal static let p_offset = 8
  internal static let p_filesz = 32
}

private enum SectionHeader {
  internal static let sh_name = 0
  internal static let sh_type = 4
  internal static let SHT_NOTE: UInt64 = 7
}

private enum Section32 {
  internal static let size: UInt64 = 40
  internal static let sh_offset = 16
  internal static let sh_size = 20
}

private enum Section64 {
  internal static let size: UInt64 = 64
  internal static let sh_offset = 24
  internal static let sh_size = 32
}

private enum Note {
  internal static let size = 12
  internal static let n_namesz = 0
  internal static let n_descsz = 4
  internal static let n_type = 8
  internal static let alignment: UInt64 = 4
  internal static let NT_GNU_BUILD_ID: UInt64 = 3
}

private enum Machine {
  internal static let EM_386: UInt64 = 3
  internal static let EM_MIPS: UInt64 = 8
  internal static let EM_PPC: UInt64 = 20
  internal static let EM_PPC64: UInt64 = 21
  internal static let EM_ARM: UInt64 = 40
  internal static let EM_X86_64: UInt64 = 62
  internal static let EM_AARCH64: UInt64 = 183
  internal static let EM_RISCV: UInt64 = 243
}

internal struct ELFModule: ~Escapable {
  private let bytes: Span<UInt8>
  private let wide: Bool
  private let little: Bool

  private var width: Int {
    wide ? MemoryLayout<UInt64>.size : MemoryLayout<UInt32>.size
  }

  @_lifetime(copy bytes)
  internal init?(_ bytes: consuming Span<UInt8>) throws(Debuggee.Error) {
    guard bytes.count >= Identification.SELFMAG,
        bytes[Identification.EI_MAG0] == Identification.ELFMAG0,
        bytes[Identification.EI_MAG1] == UInt8(ascii: "E"),
        bytes[Identification.EI_MAG2] == UInt8(ascii: "L"),
        bytes[Identification.EI_MAG3] == UInt8(ascii: "F") else {
      return nil
    }
    guard bytes.count > Identification.EI_DATA else {
      throw .process
    }
    let format = bytes[Identification.EI_CLASS]
    let order = bytes[Identification.EI_DATA]
    guard format == Identification.ELFCLASS32 ||
          format == Identification.ELFCLASS64,
        order == Identification.ELFDATA2LSB ||
        order == Identification.ELFDATA2MSB else {
      throw .process
    }
    wide = format == Identification.ELFCLASS64
    guard bytes.count >= (wide ? Header64.size : Header32.size) else {
      throw .process
    }
    little = order == Identification.ELFDATA2LSB
    self.bytes = consume bytes
  }

  internal var architecture: String {
    get throws(Debuggee.Error) {
      let machine = try integer(bytes, at: Header.e_machine,
                                count: MemoryLayout<UInt16>.size,
                                little: little)
      return switch machine {
      case Machine.EM_386: "i386"
      case Machine.EM_MIPS: wide ? "mips64" : "mips"
      case Machine.EM_PPC: "powerpc"
      case Machine.EM_PPC64: "powerpc64"
      case Machine.EM_ARM: "arm"
      case Machine.EM_X86_64: "x86_64"
      case Machine.EM_AARCH64: "aarch64"
      case Machine.EM_RISCV: wide ? "riscv64" : "riscv32"
      default: throw .process
      }
    }
  }

  internal func module(_ path: String) throws(Debuggee.Error)
      -> Debuggee.Module {
    let identity = try Debuggee.Module.Identity.unique(identifier)
    let architecture = try architecture
    return Debuggee.Module(path: path, identity: identity,
                           architecture: architecture,
                           base: Debuggee.Address(rawValue: 0),
                           size: UInt64(bytes.count))
  }

  internal var identifier: String {
    get throws(Debuggee.Error) {
      let half = MemoryLayout<UInt16>.size
      let phoff = wide ? Header64.e_phoff : Header32.e_phoff
      let phentsize = wide ? Header64.e_phentsize : Header32.e_phentsize
      let phnum = wide ? Header64.e_phnum : Header32.e_phnum
      let program = try integer(bytes, at: phoff, count: width, little: little)
      let stride =
          try integer(bytes, at: phentsize, count: half, little: little)
      let count = try integer(bytes, at: phnum, count: half, little: little)
      let size = wide ? kELF64ProgramHeaderSize : kELF32ProgramHeaderSize
      guard count == 0 || stride >= UInt64(size) else {
        throw .process
      }
      let programs = try bytes.slice(at: program, count: count, stride: stride)
      for index in 0 ..< Int(count) {
        let start = index * Int(stride)
        let entry = programs.extracting(start ..< (start + Int(stride)))
        let type = try integer(entry, at: ProgramHeader.p_type,
                               count: MemoryLayout<UInt32>.size, little: little)
        guard type == ProgramHeader.PT_NOTE else {
          continue
        }
        let location = wide ? Program64.p_offset : Program32.p_offset
        let length = wide ? Program64.p_filesz : Program32.p_filesz
        let offset =
            try integer(entry, at: location, count: width, little: little)
        let size = try integer(entry, at: length, count: width, little: little)
        if let identifier = try notes(bytes.slice(at: offset, size: size)) {
          return identifier
        }
      }
      let shoff = wide ? Header64.e_shoff : Header32.e_shoff
      let shentsize = wide ? Header64.e_shentsize : Header32.e_shentsize
      let shnum = wide ? Header64.e_shnum : Header32.e_shnum
      let shstrndx = wide ? Header64.e_shstrndx : Header32.e_shstrndx
      let section = try integer(bytes, at: shoff, count: width, little: little)
      let extent =
          try integer(bytes, at: shentsize, count: half, little: little)
      let total = try integer(bytes, at: shnum, count: half, little: little)
      let names = try integer(bytes, at: shstrndx, count: half, little: little)
      let minimum = wide ? Section64.size : Section32.size
      guard total == 0 || extent >= minimum else {
        throw .process
      }
      let sections = try bytes.slice(at: section, count: total, stride: extent)
      for index in 0 ..< Int(total) {
        let start = index * Int(extent)
        let entry = sections.extracting(start ..< (start + Int(extent)))
        let type = try integer(entry, at: SectionHeader.sh_type,
                               count: MemoryLayout<UInt32>.size, little: little)
        guard type == SectionHeader.SHT_NOTE else {
          continue
        }
        let location = wide ? Section64.sh_offset : Section32.sh_offset
        let length = wide ? Section64.sh_size : Section32.sh_size
        let offset =
            try integer(entry, at: location, count: width, little: little)
        let size = try integer(entry, at: length, count: width, little: little)
        if let identifier = try notes(bytes.slice(at: offset, size: size)) {
          return identifier
        }
      }
      if let identifier = try debuglink(sections, names: names,
                                        stride: Int(extent)) {
        return identifier
      }
      return try ModuleIdentifier.checksum(bytes)
    }
  }

  private func debuglink(_ sections: borrowing Span<UInt8>, names: UInt64,
                         stride: Int) throws(Debuggee.Error) -> String? {
    guard !sections.isEmpty, names < UInt64(sections.count / stride) else {
      return nil
    }
    let start = Int(names) * stride
    let strings = sections.extracting(start ..< (start + stride))
    let location = wide ? Section64.sh_offset : Section32.sh_offset
    let length = wide ? Section64.sh_size : Section32.sh_size
    let offset =
        try integer(strings, at: location, count: width, little: little)
    let size = try integer(strings, at: length, count: width, little: little)
    let names = try bytes.slice(at: offset, size: size)
    for start in Swift.stride(from: 0, to: sections.count, by: stride) {
      let entry = sections.extracting(start ..< (start + stride))
      let name = try integer(entry, at: SectionHeader.sh_name,
                             count: MemoryLayout<UInt32>.size, little: little)
      guard name < UInt64(names.count) else {
        continue
      }
      guard matches(names, at: Int(name), end: names.count,
                    value: ".gnu_debuglink\0") else {
        continue
      }
      let data = try integer(entry, at: location, count: width, little: little)
      let count = try integer(entry, at: length, count: width, little: little)
      let checksum = MemoryLayout<UInt32>.size
      guard count >= checksum else {
        throw .process
      }
      let contents = try bytes.slice(at: data, size: count)
      let value = try integer(contents, at: contents.count - checksum,
                              count: checksum, little: little)
      return ModuleIdentifier.encode(UInt32(value))
    }
    return nil
  }

  private func notes(_ bytes: borrowing Span<UInt8>) throws(Debuggee.Error)
      -> String? {
    var cursor = 0
    let end = bytes.count
    let word = MemoryLayout<UInt32>.size
    let padding = Note.alignment - 1
    while cursor <= end - Note.size {
      let names = try integer(bytes, at: cursor + Note.n_namesz, count: word,
                              little: little)
      let payload = try integer(bytes, at: cursor + Note.n_descsz, count: word,
                                little: little)
      let type = try integer(bytes, at: cursor + Note.n_type, count: word,
                             little: little)
      let name = cursor + Note.size
      let length = (names + padding) & ~padding
      let size = (payload + padding) & ~padding
      guard length <= UInt64(end - name),
          size <= UInt64(end - name) - length else {
        throw .process
      }
      let data = name + Int(length)
      let next = data + Int(size)
      if type == Note.NT_GNU_BUILD_ID, names >= 3,
          bytes[name + 0] == UInt8(ascii: "G"),
          bytes[name + 1] == UInt8(ascii: "N"),
          bytes[name + 2] == UInt8(ascii: "U") {
        var identifier = String()
        for index in data ..< (data + Int(payload)) {
          ModuleIdentifier.append(bytes[index], to: &identifier)
        }
        return identifier
      }
      cursor = next
    }
    return nil
  }
}

private func matches(_ bytes: borrowing Span<UInt8>, at start: Int, end: Int,
                     value: StaticString) -> Bool {
  value.withUTF8Buffer { text in
    guard text.count <= end - start else {
      return false
    }
    for index in 0 ..< text.count {
      if bytes[start + index] == text[index] {
        continue
      }
      return false
    }
    return true
  }
}
