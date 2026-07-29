// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum RegisterBytes {
  internal static func append<Value>(_ value: Value, size: Int,
                                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard output.freeCapacity >= size, size <= MemoryLayout<Value>.size else {
      throw .register
    }
    withUnsafeBytes(of: value) { bytes in
      for index in 0 ..< size {
        output.append(bytes[index])
      }
    }
  }

  internal static func extend<Value>(_ value: Value, size: Int,
                                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard output.freeCapacity >= size, MemoryLayout<Value>.size <= size else {
      throw .register
    }
    withUnsafeBytes(of: value) { bytes in
      for index in 0 ..< MemoryLayout<Value>.size {
        output.append(bytes[index])
      }
    }
    for _ in MemoryLayout<Value>.size ..< size {
      output.append(0)
    }
  }

  internal static func extend<Value>(_ value: Value, offset: Int, native: Int,
                                     size: Int,
                                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard output.freeCapacity >= size, offset >= 0, native <= size,
        offset + native <= MemoryLayout<Value>.size else {
      throw .register
    }
    withUnsafeBytes(of: value) { bytes in
      for index in 0 ..< native {
        output.append(bytes[offset + index])
      }
    }
    for _ in native ..< size {
      output.append(0)
    }
  }

  internal static func append<Value>(_ value: Value, offset: Int, size: Int,
                                     into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    guard output.freeCapacity >= size, offset >= 0,
        offset + size <= MemoryLayout<Value>.size else {
      throw .register
    }
    withUnsafeBytes(of: value) { bytes in
      for index in 0 ..< size {
        output.append(bytes[offset + index])
      }
    }
  }

  internal static func value<Value>(_ bytes: borrowing Span<UInt8>,
                                    as type: Value.Type) throws(Debuggee.Error)
      -> Value {
    guard bytes.count == MemoryLayout<Value>.size else {
      throw .register
    }
    return withUnsafeTemporaryAllocation(of: Value.self,
                                         capacity: 1) { storage in
      let raw =
          UnsafeMutableRawBufferPointer(start: storage.baseAddress,
                                        count: MemoryLayout<Value>.size)
      for index in 0 ..< bytes.count {
        raw[index] = bytes[index]
      }
      return storage[0]
    }
  }

  internal static func write<Value>(_ bytes: borrowing Span<UInt8>, offset: Int,
                                    to value: inout Value)
      throws(Debuggee.Error) {
    guard offset >= 0, offset + bytes.count <= MemoryLayout<Value>.size else {
      throw .register
    }
    withUnsafeMutableBytes(of: &value) { storage in
      for index in 0 ..< bytes.count {
        storage[offset + index] = bytes[index]
      }
    }
  }

  internal static func narrow<Value>(_ bytes: borrowing Span<UInt8>, size: Int,
                                     to value: inout Value)
      throws(Debuggee.Error) {
    guard bytes.count == size, MemoryLayout<Value>.size <= size else {
      throw .register
    }
    withUnsafeMutableBytes(of: &value) { storage in
      for index in 0 ..< MemoryLayout<Value>.size {
        storage[index] = bytes[index]
      }
    }
  }

  internal static func narrow<Value>(_ bytes: borrowing Span<UInt8>,
                                     offset: Int, native: Int, size: Int,
                                     to value: inout Value)
      throws(Debuggee.Error) {
    guard bytes.count == size, offset >= 0, native <= size,
        offset + native <= MemoryLayout<Value>.size else {
      throw .register
    }
    withUnsafeMutableBytes(of: &value) { storage in
      for index in 0 ..< native {
        storage[offset + index] = bytes[index]
      }
    }
  }
}
