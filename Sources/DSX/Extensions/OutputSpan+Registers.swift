// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension OutputSpan where Element == UInt8 {
  internal mutating func append<Value>(_ value: borrowing Value, size: Int)
      throws(Debuggee.Error) {
    guard size >= 0, freeCapacity >= size,
        size <= MemoryLayout<Value>.size else {
      throw .register
    }
    Swift.withUnsafeBytes(of: value) { bytes in
      for index in 0 ..< size {
        append(bytes[index])
      }
    }
  }

  internal mutating func extend<Value>(_ value: borrowing Value, size: Int)
      throws(Debuggee.Error) {
    guard freeCapacity >= size, MemoryLayout<Value>.size <= size else {
      throw .register
    }
    Swift.withUnsafeBytes(of: value) { bytes in
      for index in 0 ..< MemoryLayout<Value>.size {
        append(bytes[index])
      }
    }
    for _ in MemoryLayout<Value>.size ..< size {
      append(0)
    }
  }

  internal mutating func extend<Value>(_ value: borrowing Value, offset: Int,
                                       native: Int, size: Int)
      throws(Debuggee.Error) {
    guard freeCapacity >= size, offset >= 0, native >= 0, native <= size,
        offset <= MemoryLayout<Value>.size,
        native <= MemoryLayout<Value>.size - offset else {
      throw .register
    }
    Swift.withUnsafeBytes(of: value) { bytes in
      for index in 0 ..< native {
        append(bytes[offset + index])
      }
    }
    for _ in native ..< size {
      append(0)
    }
  }

  internal mutating func append<Value>(_ value: borrowing Value, offset: Int,
                                       size: Int) throws(Debuggee.Error) {
    guard freeCapacity >= size, offset >= 0, size >= 0,
        offset <= MemoryLayout<Value>.size,
        size <= MemoryLayout<Value>.size - offset else {
      throw .register
    }
    Swift.withUnsafeBytes(of: value) { bytes in
      for index in 0 ..< size {
        append(bytes[offset + index])
      }
    }
  }
}
