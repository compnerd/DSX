// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct SoftwareBreakpoint: Sendable {
  internal let size: Int
  internal var original: InlineArray<4, UInt8>

  internal init(_ process: ProcessIdentifier, _ breakpoint: BreakpointSite)
      throws(Debuggee.Error) {
    guard breakpoint.kind == .software else {
      throw .breakpoint
    }
    let address = breakpoint.address
    let size = try ABI.size(address, requested: breakpoint.size)
    guard size > 0, size <= ABI.SoftwareBreakpoint.capacity else {
      throw .breakpoint
    }
    var original: InlineArray<4, UInt8> = [0, 0, 0, 0]
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size,
                                      { data throws(Debuggee.Error) in
      var output = OutputSpan(buffer: data, initializedCount: 0)
      try NativeMemory.read(process, address: address, size: size,
                            into: &output)
      guard output.count == size else {
        throw .memory
      }
      for index in 0 ..< size {
        original[index] = output[index]
      }
    })
    self.size = size
    self.original = original
  }

  internal func enable(_ process: ProcessIdentifier,
      _ breakpoint: BreakpointSite, thread: ProcessThreadIdentifier?)
      throws(Debuggee.Error) {
    let address = breakpoint.address
    return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size,
                                             { data throws(Debuggee.Error) in
      var output = OutputSpan(buffer: data, initializedCount: 0)
      try ABI.breakpoint(size, into: &output)
      guard output.count == size else {
        throw .breakpoint
      }
      var count = 0
      do throws(Debuggee.Error) {
        try NativeMemory.patch(process, thread: thread, address: address,
                               bytes: output.span, count: &count)
      } catch {
        if count > 0 {
          try disable(process, breakpoint, thread: thread)
        }
        throw error
      }
      guard count == size else {
        if count > 0 {
          try disable(process, breakpoint, thread: thread)
        }
        throw .memory
      }
    })
  }

  internal func disable(_ process: ProcessIdentifier,
      _ breakpoint: BreakpointSite, thread: ProcessThreadIdentifier?)
      throws(Debuggee.Error) {
    let address = breakpoint.address
    var count = 0
    try NativeMemory.patch(process, thread: thread, address: address,
                           bytes: original.span.extracting(..<size),
                           count: &count)
    guard count == size else {
      throw .memory
    }
  }

  internal func overlap(_ address: Debuggee.Address, count: Int,
                        at location: Debuggee.Address)
      -> (original: Int, buffer: Int, count: Int)? {
    if location.rawValue <= address.rawValue {
      let offset = address.rawValue - location.rawValue
      guard offset < UInt64(size) else {
        return nil
      }
      return (Int(offset), 0, min(size - Int(offset), count))
    }
    let offset = location.rawValue - address.rawValue
    guard offset < UInt64(count) else {
      return nil
    }
    return (0, Int(offset), min(size, count - Int(offset)))
  }
}
