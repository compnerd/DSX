// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal struct Output: Sendable {
    internal var bytes: InlineArray<1024, UInt8>
    internal var count: Int

    internal init() {
      precondition(Configuration.OutputCapacity == 1024)
      bytes = InlineArray<1024, UInt8> { _ in 0 }
      count = 0
    }

    internal func write(into output: inout OutputSpan<UInt8>) throws(Error) {
      guard output.freeCapacity >= count else {
        throw .state
      }
      for index in 0 ..< count {
        output.append(bytes[index])
      }
    }
  }
}

internal func forward(_ process: ProcessIdentifier, current: ProcessIdentifier?,
                      pending: inout Debuggee.Output?,
                      into output: inout OutputSpan<UInt8>)
    throws(Debuggee.Error) -> Int {
  guard current == process, let bytes = pending else {
    throw .state
  }
  try bytes.write(into: &output)
  pending = nil
  return bytes.count
}
