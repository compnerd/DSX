// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func output(_ process: ProcessIdentifier,
                                writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append(UInt8(ascii: "O"))
    let capacity =
        min(Configuration.OutputCapacity, (writer.capacity - writer.count) / 2)
    guard capacity > 0 else {
      throw .capacity
    }
    let limit = Configuration.OutputCapacity
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: limit,
                                      { buffer throws(GDBHandlerError) in
      let storage = UnsafeMutableBufferPointer(rebasing: buffer[..<capacity])
      var bytes = OutputSpan(buffer: storage, initializedCount: 0)
      try translate(output(process, into: &bytes))
      for index in 0 ..< bytes.count {
        try writer.hex(bytes[index])
      }
    })
  }
}
