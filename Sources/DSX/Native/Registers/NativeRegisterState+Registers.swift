// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension NativeRegisterState {
  internal var fp: UInt64 {
    get throws(Debuggee.Error) {
      guard let record = RegisterDescription(configuration).fp else {
        throw .register
      }
      return try value(record)
    }
  }

  internal var pc: UInt64 {
    get throws(Debuggee.Error) {
      let description = RegisterDescription(configuration)
      guard let record = description.pc else {
        throw .register
      }
      return try value(record)
    }
  }

  internal mutating func set(pc: UInt64) throws(Debuggee.Error) {
    let description = RegisterDescription(configuration)
    guard let record = description.pc else {
      throw .register
    }
    let size = record.bytes
    guard size <= MemoryLayout<UInt64>.size else {
      throw .register
    }
    var bytes: InlineArray<8, UInt8> = [0, 0, 0, 0, 0, 0, 0, 0]
    for index in 0 ..< size {
      let offset = ABI.endian == .little ? index : size - index - 1
      bytes[offset] = UInt8(truncatingIfNeeded: pc >> (index * 8))
    }
    try write(record.identifier, bytes: bytes.span.extracting(..<size))
  }
}

extension NativeRegisterState {
  private func value(_ register: RegisterRecord) throws(Debuggee.Error)
      -> UInt64 {
    let size = register.bytes
    guard size <= MemoryLayout<UInt64>.size else {
      throw .register
    }
    var value: UInt64 = 0
    try withUnsafeMutableBytes(of: &value) { bytes throws(Debuggee.Error) in
      var output =
          OutputSpan(buffer: bytes.bindMemory(to: UInt8.self),
                     initializedCount: 0)
      try read(register.identifier, into: &output)
      guard output.count == size else {
        throw .register
      }
    }
    return ABI.endian == .little ? value : value >> UInt64((8 - size) * 8)
  }
}
