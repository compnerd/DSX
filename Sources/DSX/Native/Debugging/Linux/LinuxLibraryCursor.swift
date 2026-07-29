// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)

private let kLinkMapLimit = 4096
private let kPathCapacity = 4096
private let kPathChunkSize = 256

private enum DynamicEntry {
  internal static let size: Int = ABI.width.bytes * 2
  internal static let d_tag = 0
  internal static let d_un: Int = ABI.width.bytes
}

private enum AuxiliaryEntry {
  internal static let size: Int = ABI.width.bytes * 2
  internal static let a_type = 0
  internal static let a_val: Int = ABI.width.bytes
}

private enum DebugRendezvous {
  internal static let r_map: Int = ABI.width.bytes
}

private enum LinkMap {
  internal static let prefix: Int = ABI.width.bytes * 4
  internal static let l_addr = 0
  internal static let l_name: Int = ABI.width.bytes
  internal static let l_ld: Int = ABI.width.bytes * 2
  internal static let l_next: Int = ABI.width.bytes * 3
}

internal struct LinuxLibraryCursor {
  private typealias Failure = Debuggee.Error

  private let process: ProcessIdentifier
  private var link: UInt64
  private var remaining = kLinkMapLimit

  internal init(_ process: ProcessIdentifier) throws(Debuggee.Error) {
    self.process = process
    link = try process.linkage
  }

  internal mutating func next() throws(Debuggee.Error) -> Debuggee.Library? {
    while link > 0 {
      guard remaining > 0 else {
        throw .process
      }
      remaining -= 1
      let node = Debuggee.Address(rawValue: link)
      let record = try withUnsafeTemporaryAllocation(of: UInt8.self,
                                                     capacity: LinkMap.prefix,
                                                     { bytes throws(Failure) in
        var output = OutputSpan(buffer: bytes, initializedCount: 0)
        try process.read(address: link, into: &output)
        let width = ABI.width.bytes
        let little = ABI.endian == .little
        let bias = try output.span.integer(at: LinkMap.l_addr, count: width,
                                           little: little)
        let name = try output.span.integer(at: LinkMap.l_name, count: width,
                                           little: little)
        let dynamic = try output.span.integer(at: LinkMap.l_ld, count: width,
                                              little: little)
        let next = try output.span.integer(at: LinkMap.l_next, count: width,
                                           little: little)
        return (bias: bias, name: name, dynamic: dynamic, next: next)
      })
      link = record.next
      let name = record.name
      if name == 0 {
        continue
      }
      let path = try process.string(address: name)
      if path.isEmpty {
        continue
      }
      let dynamic = Debuggee.Address(rawValue: record.dynamic)
      return Debuggee.Library(path: path, bias: record.bias, link: node,
                              dynamic: dynamic)
    }
    return nil
  }
}

extension ProcessIdentifier {
  private typealias Failure = Debuggee.Error

  fileprivate var linkage: UInt64 {
    get throws(Debuggee.Error) {
      let size = switch ABI.width {
      case .b32: kELF32ProgramHeaderSize
      case .b64: kELF64ProgramHeaderSize
      case .b128: throw .process
      }
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
        let header = try withUnsafeTemporaryAllocation(of: UInt8.self,
                                                       capacity: size,
                                                       { data throws(Failure) in
          var output = OutputSpan(buffer: data, initializedCount: 0)
          try read(address: address, into: &output)
          let little = ABI.endian == .little
          let type = try output.span.integer(at: ELFProgramHeader.p_type,
                                             count: MemoryLayout<UInt32>.size,
                                             little: little)
          let origin = ABI.width == .b64
              ? ELFProgramHeader64.p_vaddr : ELFProgramHeader32.p_vaddr
          let length = ABI.width == .b64
              ? ELFProgramHeader64.p_memsz : ELFProgramHeader32.p_memsz
          let virtual = try output.span.integer(at: origin,
                                                count: ABI.width.bytes,
                                                little: little)
          let size = try output.span.integer(at: length, count: ABI.width.bytes,
                                             little: little)
          return (type: type, virtual: virtual, size: size)
        })
        let virtual = header.virtual
        switch header.type {
        case PT_PHDR:
          guard program >= virtual else {
            throw .process
          }
          bias = program - virtual
        case PT_DYNAMIC:
          dynamic = (virtual, header.size)
        default:
          break
        }
      }
      if bias == nil {
        let file = try UnixMappedFile("/proc/\(process)/exe")
        guard let module = try ELFModule(file.span()) else {
          throw .process
        }
        bias = try module.bias(at: program)
      }
      guard let bias, let dynamic else {
        throw .process
      }
      let (address, overflow) = dynamic.address.addingReportingOverflow(bias)
      if overflow {
        throw .process
      }
      let debug = try debug(address: address, size: dynamic.size)
      return try word(address: debug, offset: DebugRendezvous.r_map)
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

  fileprivate func string(address: UInt64) throws(Debuggee.Error) -> String {
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: kPathChunkSize,
                                      { buffer throws(Debuggee.Error) in
      var bytes = Array<UInt8>()
      while bytes.count < kPathCapacity {
        let count = min(buffer.count, kPathCapacity - bytes.count)
        let chunk =
            UnsafeMutableBufferPointer(start: buffer.baseAddress, count: count)
        var output = OutputSpan(buffer: chunk, initializedCount: 0)
        try read(address: address, offset: bytes.count, complete: false,
                 into: &output)
        for index in 0 ..< output.count {
          if output[index] == 0 {
            return String(decoding: bytes, as: UTF8.self)
          }
          bytes.append(output[index])
        }
      }
      throw .process
    })
  }

  private func word(address: UInt64, offset: Int = 0) throws(Debuggee.Error)
      -> UInt64 {
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: ABI.width.bytes,
                                      { buffer throws(Debuggee.Error) in
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      try read(address: address, offset: offset, into: &output)
      return try output.span.integer(at: 0, count: ABI.width.bytes,
                                     little: ABI.endian == .little)
    })
  }

  fileprivate func read(address: UInt64, offset: Int = 0, complete: Bool = true,
                        into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    let count = output.freeCapacity
    guard offset >= 0, count > 0 else {
      throw .memory
    }
    let (address, overflow) = address.addingReportingOverflow(UInt64(offset))
    guard overflow == false, UInt64(count - 1) <= UInt64.max - address else {
      throw .memory
    }
    var cursor = address
    while true {
      let initialized = output.count
      try LinuxMemory.read(self, address: Debuggee.Address(rawValue: cursor),
                           size: output.freeCapacity, into: &output)
      let received = output.count - initialized
      guard received > 0 else {
        throw .memory
      }
      if complete == false || output.freeCapacity == 0 {
        return
      }
      cursor += UInt64(received)
    }
  }
}

extension Span where Element == UInt8 {
  fileprivate func auxiliary(_ key: UInt64) throws(Debuggee.Error) -> UInt64 {
    let stride = AuxiliaryEntry.size
    let width = ABI.width.bytes
    var offset = 0
    while offset <= count, stride <= count - offset {
      let type = try integer(at: offset + AuxiliaryEntry.a_type, count: width,
                             little: ABI.endian == .little)
      switch type {
      case AT_NULL:
        throw .process
      case key:
        return try integer(at: offset + AuxiliaryEntry.a_val, count: width,
                           little: ABI.endian == .little)
      default:
        offset += stride
      }
    }
    throw .process
  }
}
#endif
