// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func emit(threads debuggee: borrowing Debuggee,
                              offset: UInt64, length: UInt64)
      throws(GDBHandlerError) {
    guard length > 0 else {
      throw .malformed
    }
    try transfer(offset: offset, length: length) { emitter in
      emitter.append("<?xml version=\"1.0\"?><threads>")
      for process in debuggee.processes {
        for thread in process.threads where debuggee.alive(thread.identifier) {
          emitter.append("<thread id=\"p")
          emitter.hex(thread.identifier.process.rawValue)
          emitter.append(UInt8(ascii: "."))
          emitter.hex(thread.identifier.thread.rawValue)
          emitter.append("\"/>")
        }
      }
      emitter.append("</threads>")
    }
  }
}
