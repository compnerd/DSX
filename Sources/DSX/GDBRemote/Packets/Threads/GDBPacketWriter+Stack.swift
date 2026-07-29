// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  @inline(__always)
  internal mutating func emit(memory process: ProcessIdentifier, frame: UInt64,
                              session: borrowing DebugSession)
      throws(GDBHandlerError) {
    let size = NativeStack.size
    var stack = NativeStack(process, frame: frame)
    var first = true
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: size,
                                      { buffer throws(GDBHandlerError) in
      while true {
        // Reserve JSON framing, the largest decimal address, and delimiters.
        guard output.freeCapacity >= size * 2 + 64 else {
          break
        }
        var output = OutputSpan(buffer: buffer, initializedCount: 0)
        guard let frame = stack.next(in: session, into: &output) else {
          break
        }
        if first {
          try append("\"memory\":[")
          first = false
        } else {
          try append(UInt8(ascii: ","))
        }
        try append("{\"address\":")
        try decimal(frame)
        try append(",\"bytes\":\"")
        for index in 0 ..< output.count {
          try hex(output[index])
        }
        try append("\"}")
      }
      if first == false {
        try append("],")
      }
    })
  }
}
