// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct SoftwareBreakpoint: Sendable {
  internal let size: Int
  internal let original: InlineArray<4, UInt8>

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
                       _ breakpoint: BreakpointSite) throws(Debuggee.Error) {
    let address = breakpoint.address
    return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size,
                                             { data throws(Debuggee.Error) in
      var output = OutputSpan(buffer: data, initializedCount: 0)
      try ABI.breakpoint(size, into: &output)
      guard output.count == size else {
        throw .breakpoint
      }
      guard try NativeMemory.write(process, address: address,
                                   bytes: output.span) == size else {
        throw .memory
      }
    })
  }

  internal func disable(_ process: ProcessIdentifier,
                        _ breakpoint: BreakpointSite) throws(Debuggee.Error) {
    let address = breakpoint.address
    let count = try NativeMemory.write(process, address: address,
                                       bytes: original.span.extracting(..<size))
    guard count == size else {
      throw .memory
    }
  }
}
