// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux)
#if os(Android)
internal import Android
#else
internal import Glibc
#endif

internal enum LinuxSVR4 {
  private static let capacity = 4096

  internal static func images(_ process: pid_t,
                              maps: consuming Array<Debuggee.Image>)
      throws(Debuggee.Error) -> Array<Debuggee.Image> {
    let auxiliary = try LinuxProcFS.contents("/proc/\(process)/auxv")
    let program = try value(auxiliary.span, key: UInt64(AT_PHDR))
    let stride = try value(auxiliary.span, key: UInt64(AT_PHENT))
    let count = try value(auxiliary.span, key: UInt64(AT_PHNUM))
    guard stride > 0, stride <= UInt64(Int.max), count <= UInt64(Int.max) else {
      throw .process
    }
    var bias: UInt64?
    var dynamic: (address: UInt64, size: UInt64)?
    for index in 0 ..< Int(count) {
      let address = program + UInt64(index) * stride
      let header = try read(process, address: address, count: Int(stride))
      let type = try integer(header.span, at: 0, count: 4)
      let virtual =
          try integer(header.span, at: ABI.word == 8 ? 16 : 8, count: ABI.word)
      let size =
          try integer(header.span, at: ABI.word == 8 ? 40 : 20, count: ABI.word)
      switch type {
      case UInt64(PT_PHDR):
        guard program >= virtual else {
          throw .process
        }
        bias = program - virtual
      case UInt64(PT_DYNAMIC):
        dynamic = (virtual, size)
      default:
        break
      }
    }
    guard let bias, let dynamic else {
      throw .process
    }
    let address = dynamic.address + bias
    let debug = try debug(process, address: address, size: dynamic.size)
    let map = try word(process, address: debug + UInt64(ABI.word))
    return try linked(process, first: map, maps: consume maps)
  }

  private static func debug(_ process: pid_t, address: UInt64,
                            size: UInt64) throws(Debuggee.Error) -> UInt64 {
    let stride = UInt64(ABI.word * 2)
    guard size / stride <= UInt64(Int.max) else {
      throw .process
    }
    for index in 0 ..< Int(size / stride) {
      let entry = address + UInt64(index) * stride
      let tag = try word(process, address: entry)
      if tag == 0 {
        break
      }
      if tag == UInt64(DT_DEBUG) {
        return try word(process, address: entry + UInt64(ABI.word))
      }
    }
    throw .process
  }

  private static func linked(_ process: pid_t, first: UInt64,
                             maps: consuming Array<Debuggee.Image>)
      throws(Debuggee.Error) -> Array<Debuggee.Image> {
    var images = consume maps
    var link = first
    for _ in 0 ..< capacity {
      guard link > 0 else {
        break
      }
      let record = try read(process, address: link, count: ABI.word * 4)
      let base = try integer(record.span, at: 0, count: ABI.word)
      let name = try integer(record.span, at: ABI.word, count: ABI.word)
      let dynamic = try integer(record.span, at: ABI.word * 2, count: ABI.word)
      let next = try integer(record.span, at: ABI.word * 3, count: ABI.word)
      if base > 0, name > 0 {
        let path = try string(process, address: name)
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

  private static func string(_ process: pid_t,
                             address: UInt64) throws(Debuggee.Error) -> String {
    var bytes = Array<UInt8>()
    while bytes.count < capacity {
      let chunk = try read(process, address: address + UInt64(bytes.count),
                           count: min(256, capacity - bytes.count))
      if let end = chunk.firstIndex(of: 0) {
        bytes.append(contentsOf: chunk[..<end])
        return String(decoding: bytes, as: UTF8.self)
      }
      bytes.append(contentsOf: chunk)
    }
    throw .process
  }

  private static func word(_ process: pid_t,
                           address: UInt64) throws(Debuggee.Error) -> UInt64 {
    let bytes = try read(process, address: address, count: ABI.word)
    return try integer(bytes.span, at: 0, count: ABI.word,
                       little: ABI.endian == .little)
  }

  private static func read(_ process: pid_t, address: UInt64,
                           count: Int) throws(Debuggee.Error) -> Array<UInt8> {
    var bytes = Array(repeating: UInt8(0), count: count)
    var initialized = 0
    try bytes.withUnsafeMutableBufferPointer { buffer throws(Debuggee.Error) in
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      let identifier = ProcessIdentifier(rawValue: UInt64(process))
      try LinuxMemory.read(identifier,
                           address: Debuggee.Address(rawValue: address),
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

  private static func value(_ bytes: borrowing Span<UInt8>,
                            key: UInt64) throws(Debuggee.Error) -> UInt64 {
    let stride = ABI.word * 2
    var offset = 0
    while offset + stride <= bytes.count {
      let type = try integer(bytes, at: offset, count: ABI.word,
                             little: ABI.endian == .little)
      switch type {
      case 0:
        throw .process
      case key:
        return try integer(bytes, at: offset + ABI.word, count: ABI.word,
                           little: ABI.endian == .little)
      default:
        offset += stride
      }
    }
    throw .process
  }
}
#endif
