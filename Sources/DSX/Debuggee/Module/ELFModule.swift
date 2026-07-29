// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct ELFModule: ~Escapable {
  private let bytes: Span<UInt8>
  private let wide: Bool
  private let little: Bool

  @_lifetime(copy bytes)
  internal init?(_ bytes: consuming Span<UInt8>) throws(Debuggee.Error) {
    guard bytes.count >= 4, bytes[0] == 0x7f,
        bytes[1] == UInt8(ascii: "E"), bytes[2] == UInt8(ascii: "L"),
        bytes[3] == UInt8(ascii: "F") else {
      return nil
    }
    guard bytes.count >= 6, bytes[4] == 1 || bytes[4] == 2,
        bytes[5] == 1 || bytes[5] == 2 else {
      throw .process
    }
    wide = bytes[4] == 2
    guard bytes.count >= (wide ? 64 : 52) else {
      throw .process
    }
    little = bytes[5] == 1
    self.bytes = consume bytes
  }

  internal var architecture: String {
    get throws(Debuggee.Error) {
      let machine = try integer(bytes, at: 18, count: 2, little: little)
      return switch machine {
      case 3: "i386"
      case 8: wide ? "mips64" : "mips"
      case 20: "powerpc"
      case 21: "powerpc64"
      case 40: "arm"
      case 62: "x86_64"
      case 183: "aarch64"
      case 243: wide ? "riscv64" : "riscv32"
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
      let program = try integer(bytes, at: wide ? 32 : 28, count: wide ? 8 : 4,
                                little: little)
      let stride =
          try integer(bytes, at: wide ? 54 : 42, count: 2, little: little)
      let count =
          try integer(bytes, at: wide ? 56 : 44, count: 2, little: little)
      guard count == 0 || stride >= (wide ? 56 : 32) else {
        throw .process
      }
      let programs = try bytes.slice(at: program, count: count, stride: stride)
      for index in 0 ..< Int(count) {
        let start = index * Int(stride)
        let entry = programs.extracting(start ..< (start + Int(stride)))
        guard try integer(entry, at: 0, count: 4, little: little) == 4 else {
          continue
        }
        let offset = try integer(entry, at: wide ? 8 : 4, count: wide ? 8 : 4,
                                 little: little)
        let size = try integer(entry, at: wide ? 32 : 16, count: wide ? 8 : 4,
                               little: little)
        if let identifier = try notes(bytes.slice(at: offset, size: size)) {
          return identifier
        }
      }
      let section = try integer(bytes, at: wide ? 40 : 32, count: wide ? 8 : 4,
                                little: little)
      let width =
          try integer(bytes, at: wide ? 58 : 46, count: 2, little: little)
      let total =
          try integer(bytes, at: wide ? 60 : 48, count: 2, little: little)
      let names =
          try integer(bytes, at: wide ? 62 : 50, count: 2, little: little)
      guard total == 0 || width >= (wide ? 64 : 40) else {
        throw .process
      }
      let sections = try bytes.slice(at: section, count: total, stride: width)
      for index in 0 ..< Int(total) {
        let start = index * Int(width)
        let entry = sections.extracting(start ..< (start + Int(width)))
        guard try integer(entry, at: 4, count: 4, little: little) == 7 else {
          continue
        }
        let offset = try integer(entry, at: wide ? 24 : 16, count: wide ? 8 : 4,
                                 little: little)
        let size = try integer(entry, at: wide ? 32 : 20, count: wide ? 8 : 4,
                               little: little)
        if let identifier = try notes(bytes.slice(at: offset, size: size)) {
          return identifier
        }
      }
      if let identifier = try debuglink(sections, names: names,
                                        stride: Int(width)) {
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
    let offset = try integer(strings, at: wide ? 24 : 16, count: wide ? 8 : 4,
                             little: little)
    let size = try integer(strings, at: wide ? 32 : 20, count: wide ? 8 : 4,
                           little: little)
    let names = try bytes.slice(at: offset, size: size)
    for start in Swift.stride(from: 0, to: sections.count, by: stride) {
      let entry = sections.extracting(start ..< (start + stride))
      let name = try integer(entry, at: 0, count: 4, little: little)
      guard name < UInt64(names.count) else {
        continue
      }
      guard matches(names, at: Int(name), end: names.count,
                    value: ".gnu_debuglink\0") else {
        continue
      }
      let data = try integer(entry, at: wide ? 24 : 16, count: wide ? 8 : 4,
                             little: little)
      let count = try integer(entry, at: wide ? 32 : 20, count: wide ? 8 : 4,
                              little: little)
      guard count >= 4 else {
        throw .process
      }
      let contents = try bytes.slice(at: data, size: count)
      let value = try integer(contents, at: contents.count - 4, count: 4,
                              little: little)
      return ModuleIdentifier.encode(UInt32(value))
    }
    return nil
  }

  private func notes(_ bytes: borrowing Span<UInt8>) throws(Debuggee.Error)
      -> String? {
    var cursor = 0
    let end = bytes.count
    while cursor <= end - 12 {
      let names = try integer(bytes, at: cursor, count: 4, little: little)
      let payload = try integer(bytes, at: cursor + 4, count: 4, little: little)
      let type = try integer(bytes, at: cursor + 8, count: 4, little: little)
      let name = cursor + 12
      let length = (names + 3) & ~UInt64(3)
      let size = (payload + 3) & ~UInt64(3)
      guard length <= UInt64(end - name),
          size <= UInt64(end - name) - length else {
        throw .process
      }
      let data = name + Int(length)
      let next = data + Int(size)
      if type == 3, names >= 3, bytes[name] == UInt8(ascii: "G"),
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
