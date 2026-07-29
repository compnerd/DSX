// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Span where Element == UInt8 {
  internal func register<Value: BitwiseCopyable>(as type: Value.Type)
      throws(Debuggee.Error) -> Value {
    guard count == MemoryLayout<Value>.size else {
      throw .register
    }
    return withUnsafeBufferPointer { bytes in
      UnsafeRawBufferPointer(bytes).loadUnaligned(as: type)
    }
  }

  internal func write<Value>(offset: Int, to value: inout Value)
      throws(Debuggee.Error) {
    guard offset >= 0, offset <= MemoryLayout<Value>.size,
        count <= MemoryLayout<Value>.size - offset else {
      throw .register
    }
    withUnsafeMutableBytes(of: &value) { storage in
      for index in 0 ..< count {
        storage[offset + index] = self[index]
      }
    }
  }

  internal func narrow<Value>(size: Int, to value: inout Value)
      throws(Debuggee.Error) {
    guard count == size, MemoryLayout<Value>.size <= size else {
      throw .register
    }
    withUnsafeMutableBytes(of: &value) { storage in
      for index in 0 ..< MemoryLayout<Value>.size {
        storage[index] = self[index]
      }
    }
  }

  internal func narrow<Value>(offset: Int, native: Int, size: Int,
                              to value: inout Value) throws(Debuggee.Error) {
    guard count == size, offset >= 0, native >= 0, native <= size,
        offset <= MemoryLayout<Value>.size,
        native <= MemoryLayout<Value>.size - offset else {
      throw .register
    }
    withUnsafeMutableBytes(of: &value) { storage in
      for index in 0 ..< native {
        storage[offset + index] = self[index]
      }
    }
  }
}
