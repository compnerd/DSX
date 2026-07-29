// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBConsoleOutputPacket {
  internal static func write(_ process: ProcessIdentifier,
                             session: inout DebugSession,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    try writer.append(UInt8(ascii: "O"))
    let capacity = Configuration.OutputCapacity
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                      { buffer throws(GDBHandlerError) in
      var output = OutputSpan(buffer: buffer, initializedCount: 0)
      try translate(session.output(process, into: &output))
      for index in 0 ..< output.count {
        try writer.hex(output[index])
      }
    })
  }
}
