// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func transfer(offset: UInt64, length: UInt64,
                                  _ body: GDBTransferEmitterBody)
      throws(GDBHandlerError) {
    let marker = output.count
    let limit = try begin(length)
    var emitter =
        GDBTransferEmitter(consume output, offset: offset, limit: limit)
    var failure: Debuggee.Error?
    do throws(Debuggee.Error) {
      try body(&emitter)
    } catch {
      failure = error
    }
    let more = emitter.more
    self = GDBPacketWriter(emitter.finish())
    if let failure {
      throw .debuggee(failure)
    }
    output[marker] = more ? UInt8(ascii: "m") : UInt8(ascii: "l")
  }

  internal mutating func transfer(length: UInt64, body: GDBTransferBody)
      throws(GDBHandlerError) {
    let marker = output.count
    let limit = try begin(length)
    let start = output.count
    let status = try translate(body(limit, &output))
    guard output.count - start <= limit else {
      throw .capacity
    }
    output[marker] = switch status {
    case .last: UInt8(ascii: "l")
    case .more: UInt8(ascii: "m")
    }
  }

  private mutating func begin(_ length: UInt64) throws(GDBHandlerError) -> Int {
    guard output.freeCapacity > 0 else {
      throw .capacity
    }
    let requested = min(length, UInt64(Int.max))
    let limit = min(Int(requested), output.freeCapacity - 1)
    try append(0x00)
    return limit
  }
}

internal typealias GDBTransferBody =
    (Int, inout OutputSpan<UInt8>) throws(Debuggee.Error) -> ReadStatus
internal typealias GDBTransferEmitterBody =
    (inout GDBTransferEmitter) throws(Debuggee.Error) -> Void
