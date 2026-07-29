// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension NativeRegisterState {
  internal func read(_ register: RegisterRecord, container: RegisterRecord?,
                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard let container else {
      return try read(register.identifier, into: &output)
    }
    let count = register.bytes
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: container.bytes,
                                      { buffer throws(Debuggee.Error) in
      var bytes = OutputSpan(buffer: buffer, initializedCount: 0)
      try read(container.identifier, into: &bytes)
      guard bytes.count >= count, output.freeCapacity >= count else {
        throw .register
      }
      let start = ABI.endian == .little ? 0 : bytes.count - count
      for index in start ..< (start + count) {
        output.append(bytes[index])
      }
    })
  }

  internal mutating func write(_ register: RegisterRecord,
                               container: RegisterRecord?,
                               bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    guard let container else {
      return try write(register.identifier, bytes: bytes)
    }
    let count = register.bytes
    let size = container.bytes
    guard bytes.count == count, count <= size else {
      throw .register
    }
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size,
                                      { buffer throws(Debuggee.Error) in
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      try read(container.identifier, into: &output)
      guard output.count == size else {
        throw .register
      }
      let start = ABI.endian == .little ? 0 : size - count
      for index in 0 ..< count {
        output[start + index] = bytes[index]
      }
      if case .unsigned = register.encoding, register.bits == 32,
          container.bits == 64 {
        let start = ABI.endian == .little ? count : 0
        for index in start ..< (start + size - count) {
          output[index] = 0
        }
      }
      try write(container.identifier, bytes: output.span)
    })
  }
}
