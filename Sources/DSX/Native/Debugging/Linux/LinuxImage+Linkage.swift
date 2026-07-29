// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)

private let kLinkMapLimit = 4096
private let kPathCapacity = 4096
private let kPathChunkSize = 256

private enum ProgramHeader {
  internal static let p_type = 0
  internal static var p_vaddr: Int { ABI.width == .b64 ? 16 : 8 }
  internal static var p_memsz: Int { ABI.width == .b64 ? 40 : 20 }
}

private enum DynamicEntry {
  internal static var size: Int { ABI.width.bytes * 2 }
  internal static let d_tag = 0
  internal static var d_un: Int { ABI.width.bytes }
}

private enum AuxiliaryEntry {
  internal static var size: Int { ABI.width.bytes * 2 }
  internal static let a_type = 0
  internal static var a_val: Int { ABI.width.bytes }
}

private enum DebugRendezvous {
  internal static var r_map: Int { ABI.width.bytes }
}

private enum LinkMap {
  internal static var prefix: Int { ABI.width.bytes * 4 }
  internal static let l_addr = 0
  internal static var l_name: Int { ABI.width.bytes }
  internal static var l_ld: Int { ABI.width.bytes * 2 }
  internal static var l_next: Int { ABI.width.bytes * 3 }
}

extension ProcessIdentifier {
  internal var linkage: Array<Debuggee.Image> {
    get throws(Debuggee.Error) {
      let size = switch ABI.width {
      case .b32: kELF32ProgramHeaderSize
      case .b64: kELF64ProgramHeaderSize
      case .b128: throw .process
      }
      let maps = try images(.name)
      let process = try native
      let bytes = try LinuxProcFS.contents("/proc/\(process)/auxv")
      let program = try bytes.span.auxiliary(AT_PHDR)
      let stride = try bytes.span.auxiliary(AT_PHENT)
      let count = try bytes.span.auxiliary(AT_PHNUM)
      guard stride == UInt64(size), count > 0, count <= UInt64(Int.max),
          count <= (UInt64.max - program) / stride else {
        throw .process
      }
      var bias: UInt64?
      var dynamic: (address: UInt64, size: UInt64)?
      for index in 0 ..< Int(count) {
        let address = program + UInt64(index) * stride
        let header = try read(address: address, count: Int(stride))
        let little = ABI.endian == .little
        let type = try integer(header.span, at: ProgramHeader.p_type,
                               count: MemoryLayout<UInt32>.size, little: little)
        let virtual = try integer(header.span, at: ProgramHeader.p_vaddr,
                                  count: ABI.width.bytes, little: little)
        let size = try integer(header.span, at: ProgramHeader.p_memsz,
                               count: ABI.width.bytes, little: little)
        switch type {
        case PT_PHDR:
          guard program >= virtual else {
            throw .process
          }
          bias = program - virtual
        case PT_DYNAMIC:
          dynamic = (virtual, size)
        default:
          break
        }
      }
      guard let bias, let dynamic else {
        throw .process
      }
      let (address, overflow) = dynamic.address.addingReportingOverflow(bias)
      if overflow {
        throw .process
      }
      let debug = try debug(address: address, size: dynamic.size)
      let map = try word(address: debug, offset: DebugRendezvous.r_map)
      return try linked(first: map, maps: consume maps)
    }
  }

  private func debug(address: UInt64, size: UInt64) throws(Debuggee.Error)
      -> UInt64 {
    let stride = UInt64(DynamicEntry.size)
    guard size <= UInt64.max - address, size / stride <= UInt64(Int.max) else {
      throw .process
    }
    for index in 0 ..< Int(size / stride) {
      let entry = address + UInt64(index) * stride
      let tag = try word(address: entry, offset: DynamicEntry.d_tag)
      if tag == DT_NULL {
        break
      }
      if tag == DT_DEBUG {
        return try word(address: entry + UInt64(DynamicEntry.d_un))
      }
    }
    throw .process
  }

  private func linked(first: UInt64, maps: consuming Array<Debuggee.Image>)
      throws(Debuggee.Error) -> Array<Debuggee.Image> {
    var images = consume maps
    var link = first
    let width = ABI.width.bytes
    for _ in 0 ..< kLinkMapLimit {
      guard link > 0 else {
        break
      }
      let record = try read(address: link, count: LinkMap.prefix)
      let little = ABI.endian == .little
      let base = try integer(record.span, at: LinkMap.l_addr, count: width,
                             little: little)
      let name = try integer(record.span, at: LinkMap.l_name, count: width,
                             little: little)
      let dynamic = try integer(record.span, at: LinkMap.l_ld, count: width,
                                little: little)
      let next = try integer(record.span, at: LinkMap.l_next, count: width,
                             little: little)
      if base > 0, name > 0 {
        let path = try string(address: name)
        guard !path.isEmpty else {
          link = next
          continue
        }
        let address = Debuggee.Address(rawValue: base)
        let node = Debuggee.Address(rawValue: link)
        let table = Debuggee.Address(rawValue: dynamic)
        if let index = images.firstIndex(where: { image in
            image.base == address
        }) {
          let image = images[index]
          images[index] = Debuggee.Image(path: image.path, base: image.base,
                                         sections: image.sections,
                                         main: image.main, system: image.system,
                                         description: image.description,
                                         link: node, dynamic: table)
        } else {
          images.append(Debuggee.Image(path: path, base: address, link: node,
                                       dynamic: table))
        }
      }
      link = next
    }
    return images
  }

  private func string(address: UInt64) throws(Debuggee.Error) -> String {
    var bytes = Array<UInt8>()
    while bytes.count < kPathCapacity {
      let count = min(kPathChunkSize, kPathCapacity - bytes.count)
      let chunk = try read(address: address, offset: bytes.count, count: count)
      if let end = chunk.firstIndex(of: 0) {
        bytes.append(contentsOf: chunk[..<end])
        return String(decoding: bytes, as: UTF8.self)
      }
      bytes.append(contentsOf: chunk)
    }
    throw .process
  }

  private func word(address: UInt64, offset: Int = 0) throws(Debuggee.Error)
      -> UInt64 {
    let bytes =
        try read(address: address, offset: offset, count: ABI.width.bytes)
    return try integer(bytes.span, at: 0, count: ABI.width.bytes,
                       little: ABI.endian == .little)
  }

  private func read(address: UInt64, offset: Int = 0, count: Int)
      throws(Debuggee.Error) -> Array<UInt8> {
    guard offset >= 0, count > 0 else {
      throw .memory
    }
    let (address, overflow) = address.addingReportingOverflow(UInt64(offset))
    guard overflow == false, UInt64(count - 1) <= UInt64.max - address else {
      throw .memory
    }
    var bytes = Array(repeating: UInt8(0), count: count)
    var initialized = 0
    try bytes.withUnsafeMutableBufferPointer { buffer throws(Debuggee.Error) in
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      try LinuxMemory.read(self, address: Debuggee.Address(rawValue: address),
                           size: count, into: &output)
      initialized = output.count
    }
    guard initialized > 0 else {
      throw .memory
    }
    if initialized < bytes.count {
      bytes.removeLast(bytes.count - initialized)
    }
    return bytes
  }
}

extension Span where Element == UInt8 {
  fileprivate func auxiliary(_ key: UInt64) throws(Debuggee.Error) -> UInt64 {
    let stride = AuxiliaryEntry.size
    let width = ABI.width.bytes
    var offset = 0
    while offset <= count, stride <= count - offset {
      let type = try integer(self, at: offset + AuxiliaryEntry.a_type,
                             count: width, little: ABI.endian == .little)
      switch type {
      case AT_NULL:
        throw .process
      case key:
        return try integer(self, at: offset + AuxiliaryEntry.a_val,
                           count: width, little: ABI.endian == .little)
      default:
        offset += stride
      }
    }
    throw .process
  }
}
#endif
