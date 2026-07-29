// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBThreadTransferPacket {
  internal static func write(offset: UInt64, length: UInt64,
                             debuggee: borrowing Debuggee,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard length > 0 else {
      throw .malformed
    }
    try writer.transfer(offset: offset, length: length) { emitter, output in
      emitter.append("<?xml version=\"1.0\"?><threads>", into: &output)
      for process in debuggee.processes {
        for thread in process.threads where debuggee.alive(thread.identifier) {
          emitter.append("<thread id=\"p", into: &output)
          emitter.hex(thread.identifier.process.rawValue, into: &output)
          emitter.append(UInt8(ascii: "."), into: &output)
          emitter.hex(thread.identifier.thread.rawValue, into: &output)
          emitter.append("\"/>", into: &output)
        }
      }
      emitter.append("</threads>", into: &output)
    }
  }
}
