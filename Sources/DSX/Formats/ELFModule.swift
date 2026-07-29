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

internal enum ELFProgramHeader {
  internal static let p_type = 0
  internal static let PT_LOAD: UInt64 = 1
  internal static let PT_NOTE: UInt64 = 4
}

internal enum ELFProgramHeader32 {
  internal static let p_offset = 4
  internal static let p_vaddr = 8
  internal static let p_filesz = 16
  internal static let p_memsz = 20
}

internal enum ELFProgramHeader64 {
  internal static let p_offset = 8
  internal static let p_vaddr = 16
  internal static let p_filesz = 32
  internal static let p_memsz = 40
}

private enum SectionHeader {
  internal static let sh_name = 0
  internal static let sh_type = 4
  internal static let SHT_NOTE: UInt64 = 7
  internal static let SHN_XINDEX: UInt64 = 0xffff
}

private enum Section32 {
  internal static let size: UInt64 = 40
  internal static let sh_offset = 16
  internal static let sh_size = 20
  internal static let sh_link = 24
}

private enum Section64 {
  internal static let size: UInt64 = 64
  internal static let sh_offset = 24
  internal static let sh_size = 32
  internal static let sh_link = 40
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

  internal var size: UInt64 {
    UInt64(bytes.count)
  }

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

  private var e_phoff: UInt64 {
    get throws(Debuggee.Error) {
      let offset = wide ? Header64.e_phoff : Header32.e_phoff
      return try bytes.integer(at: offset, count: width, little: little)
    }
  }

  private var e_phentsize: UInt64 {
    get throws(Debuggee.Error) {
      let offset = wide ? Header64.e_phentsize : Header32.e_phentsize
      return try bytes.integer(at: offset, count: 2, little: little)
    }
  }

  private var programs: Span<UInt8> {
    @_lifetime(copy self)
    get throws(Debuggee.Error) {
      let offset = wide ? Header64.e_phnum : Header32.e_phnum
      let count = try bytes.integer(at: offset, count: 2, little: little)
      let stride = try e_phentsize
      let size = wide ? kELF64ProgramHeaderSize : kELF32ProgramHeaderSize
      guard count == 0 || stride >= UInt64(size) else {
        throw .process
      }
      return try bytes.slice(at: e_phoff, count: count, stride: stride)
    }
  }

  internal func bias(at address: UInt64) throws(Debuggee.Error) -> UInt64 {
    let offset = try e_phoff
    let stride = try e_phentsize
    let programs = try programs
    guard !programs.isEmpty else {
      throw .process
    }
    for start in Swift.stride(from: 0, to: programs.count, by: Int(stride)) {
      let entry = programs.extracting(start ..< (start + Int(stride)))
      let type = try entry.integer(at: ELFProgramHeader.p_type,
                                   count: MemoryLayout<UInt32>.size,
                                   little: little)
      guard type == ELFProgramHeader.PT_LOAD else {
        continue
      }
      let location =
          wide ? ELFProgramHeader64.p_offset : ELFProgramHeader32.p_offset
      let length =
          wide ? ELFProgramHeader64.p_filesz : ELFProgramHeader32.p_filesz
      let origin =
          wide ? ELFProgramHeader64.p_vaddr : ELFProgramHeader32.p_vaddr
      let file = try entry.integer(at: location, count: width, little: little)
      let size = try entry.integer(at: length, count: width, little: little)
      guard offset >= file, offset - file <= size,
          UInt64(programs.count) <= size - (offset - file) else {
        continue
      }
      let virtual = try entry.integer(at: origin, count: width, little: little)
      let (program, overflow) = virtual.addingReportingOverflow(offset - file)
      guard overflow == false, address >= program else {
        throw .process
      }
      return address - program
    }
    throw .process
  }

  internal var extent: Range<UInt64> {
    get throws(Debuggee.Error) {
      let stride = try e_phentsize
      let programs = try programs
      guard !programs.isEmpty else {
        throw .process
      }
      var lower = UInt64.max
      var upper: UInt64 = 0
      for start in Swift.stride(from: 0, to: programs.count, by: Int(stride)) {
        let entry = programs.extracting(start ..< (start + Int(stride)))
        let type = try entry.integer(at: ELFProgramHeader.p_type,
                                     count: MemoryLayout<UInt32>.size,
                                     little: little)
        guard type == ELFProgramHeader.PT_LOAD else {
          continue
        }
        let origin =
            wide ? ELFProgramHeader64.p_vaddr : ELFProgramHeader32.p_vaddr
        let length =
            wide ? ELFProgramHeader64.p_memsz : ELFProgramHeader32.p_memsz
        let address =
            try entry.integer(at: origin, count: width, little: little)
        let size = try entry.integer(at: length, count: width, little: little)
        guard size > 0 else {
          continue
        }
        let (end, overflow) = address.addingReportingOverflow(size)
        guard overflow == false else {
          throw .process
        }
        lower = min(lower, address)
        upper = max(upper, end)
      }
      guard lower < upper else {
        throw .process
      }
      return lower ..< upper
    }
  }

  internal var architecture: String {
    get throws(Debuggee.Error) {
      let machine = try bytes.integer(at: Header.e_machine,
                                      count: MemoryLayout<UInt16>.size,
                                      little: little)
      return switch machine {
      case Machine.EM_386: "i386"
      case Machine.EM_MIPS:
        switch (wide, little) {
        case (false, false): "mips"
        case (false, true): "mipsel"
        case (true, false): "mips64"
        case (true, true): "mips64el"
        }
      case Machine.EM_PPC: little ? "powerpcle" : "powerpc"
      case Machine.EM_PPC64: little ? "powerpc64le" : "powerpc64"
      case Machine.EM_ARM: little ? "arm" : "armeb"
      case Machine.EM_X86_64: "x86_64"
      case Machine.EM_AARCH64: little ? "aarch64" : "aarch64_be"
      case Machine.EM_RISCV: wide ? "riscv64" : "riscv32"
      default: throw .process
      }
    }
  }

  internal var identifier: String {
    get throws(Debuggee.Error) {
      let half = MemoryLayout<UInt16>.size
      let stride = try max(1, e_phentsize)
      let programs = try programs
      for start in Swift.stride(from: 0, to: programs.count, by: Int(stride)) {
        let entry = programs.extracting(start ..< (start + Int(stride)))
        let type = try entry.integer(at: ELFProgramHeader.p_type,
                                     count: MemoryLayout<UInt32>.size,
                                     little: little)
        guard type == ELFProgramHeader.PT_NOTE else {
          continue
        }
        let location =
            wide ? ELFProgramHeader64.p_offset : ELFProgramHeader32.p_offset
        let length =
            wide ? ELFProgramHeader64.p_filesz : ELFProgramHeader32.p_filesz
        let offset =
            try entry.integer(at: location, count: width, little: little)
        let size = try entry.integer(at: length, count: width, little: little)
        if let identifier = try notes(bytes.slice(at: offset, size: size)) {
          return identifier
        }
      }
      let shoff = wide ? Header64.e_shoff : Header32.e_shoff
      let shentsize = wide ? Header64.e_shentsize : Header32.e_shentsize
      let shnum = wide ? Header64.e_shnum : Header32.e_shnum
      let shstrndx = wide ? Header64.e_shstrndx : Header32.e_shstrndx
      let section = try bytes.integer(at: shoff, count: width, little: little)
      let extent = try bytes.integer(at: shentsize, count: half, little: little)
      var total = try bytes.integer(at: shnum, count: half, little: little)
      var names = try bytes.integer(at: shstrndx, count: half, little: little)
      let minimum = wide ? Section64.size : Section32.size
      // Extended section numbering stores the count and string index in
      // section zero (ELF gABI, ELF Header: e_shnum and e_shstrndx).
      if section > 0, total == 0 || names == SectionHeader.SHN_XINDEX {
        guard extent >= minimum else {
          throw .process
        }
        let initial = try bytes.slice(at: section, size: minimum)
        if total == 0 {
          let offset = wide ? Section64.sh_size : Section32.sh_size
          total = try initial.integer(at: offset, count: width, little: little)
        }
        if names == SectionHeader.SHN_XINDEX {
          let offset = wide ? Section64.sh_link : Section32.sh_link
          names = try initial.integer(at: offset, count: 4, little: little)
        }
      }
      guard total == 0 || extent >= minimum else {
        throw .process
      }
      let sections = try bytes.slice(at: section, count: total, stride: extent)
      for index in 0 ..< Int(total) {
        let start = index * Int(extent)
        let entry = sections.extracting(start ..< (start + Int(extent)))
        let type = try entry.integer(at: SectionHeader.sh_type,
                                     count: MemoryLayout<UInt32>.size,
                                     little: little)
        guard type == SectionHeader.SHT_NOTE else {
          continue
        }
        let location = wide ? Section64.sh_offset : Section32.sh_offset
        let length = wide ? Section64.sh_size : Section32.sh_size
        let offset =
            try entry.integer(at: location, count: width, little: little)
        let size = try entry.integer(at: length, count: width, little: little)
        if let identifier = try notes(bytes.slice(at: offset, size: size)) {
          return identifier
        }
      }
      if let identifier = try debuglink(sections, names: names,
                                        stride: Int(extent)) {
        return identifier
      }
      return try String(checksum: bytes)
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
    let offset = try strings.integer(at: location, count: width, little: little)
    let size = try strings.integer(at: length, count: width, little: little)
    let names = try bytes.slice(at: offset, size: size)
    for start in Swift.stride(from: 0, to: sections.count, by: stride) {
      let entry = sections.extracting(start ..< (start + stride))
      let name = try entry.integer(at: SectionHeader.sh_name,
                                   count: MemoryLayout<UInt32>.size,
                                   little: little)
      guard name < UInt64(names.count) else {
        continue
      }
      guard names.matches(at: Int(name), value: ".gnu_debuglink\0") else {
        continue
      }
      let data = try entry.integer(at: location, count: width, little: little)
      let count = try entry.integer(at: length, count: width, little: little)
      return try String(debuglink: bytes.slice(at: data, size: count),
                        little: little)
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
      let names = try bytes.integer(at: cursor + Note.n_namesz, count: word,
                                    little: little)
      let payload = try bytes.integer(at: cursor + Note.n_descsz, count: word,
                                      little: little)
      let type = try bytes.integer(at: cursor + Note.n_type, count: word,
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
      if type == Note.NT_GNU_BUILD_ID, names == 4, payload >= 4,
          bytes[name + 0] == UInt8(ascii: "G"),
          bytes[name + 1] == UInt8(ascii: "N"),
          bytes[name + 2] == UInt8(ascii: "U"), bytes[name + 3] == 0 {
        var identifier = String()
        for index in data ..< (data + Int(payload)) {
          identifier.append(hex: bytes[index])
        }
        return identifier
      }
      cursor = next
    }
    return nil
  }
}
