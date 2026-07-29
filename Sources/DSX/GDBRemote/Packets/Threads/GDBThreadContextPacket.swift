// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBThreadContextPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: borrowing DebugSession,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard let layout = try parse(payload) else {
      return try writer.append("OK")
    }
    guard let thread = session.debuggee.resolve(layout.thread) else {
      throw .debuggee(.thread)
    }
    let context = try translate(thread.context(layout))
    try writer.append(UInt8(ascii: "{"))
    var first = true
    try field("pthread_t", value: context.pthread, first: &first,
              writer: &writer)
    try field("tsd_address", value: context.storage, first: &first,
              writer: &writer)
    try field("dispatch_queue_t", value: context.queue, first: &first,
              writer: &writer)
    try writer.append(UInt8(ascii: "}"))
  }
}

private func parse(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError)
    -> Debuggee.Thread.Layout? {
  var reader = GDBPacketReader(payload.extracting(0...))
  guard reader.consume(UInt8(ascii: ":")) else {
    throw .malformed
  }
  if reader.empty {
    return nil
  }
  guard reader.consume(UInt8(ascii: "{")) else {
    throw .malformed
  }
  var thread: UInt64?
  var address: UInt64?
  var base: UInt64?
  var size: UInt64?
  let absolute: StaticString = "plo_pthread_tsd_base_address_offset"
  while true {
    guard reader.consume(UInt8(ascii: "\"")) else {
      throw .malformed
    }
    let key = try reader.field(UInt8(ascii: "\""))
    guard reader.consume(UInt8(ascii: ":")) else {
      throw .malformed
    }
    let value = try reader.decimal()
    switch () {
    case () where reader.matches(key, value: "thread"):
      thread = value
    case () where reader.matches(key, value: absolute):
      address = value
    case () where reader.matches(key, value: "plo_pthread_tsd_base_offset"):
      base = value
    case () where reader.matches(key, value: "plo_pthread_tsd_entry_size"):
      size = value
    default:
      break
    }
    if reader.consume(UInt8(ascii: "}")) {
      break
    }
    guard reader.consume(UInt8(ascii: ",")) else {
      throw .malformed
    }
  }
  guard reader.empty, let thread, let address, let base, let size else {
    throw .malformed
  }
  let identifier = ThreadIdentifier(rawValue: thread)
  return Debuggee.Thread.Layout(thread: identifier, address: address,
                                base: base, size: size)
}

private func field(_ name: StaticString, value: UInt64?, first: inout Bool,
                   writer: inout GDBPacketWriter) throws(GDBHandlerError) {
  guard let value else {
    return
  }
  if first {
    first = false
  } else {
    try writer.append(UInt8(ascii: ","))
  }
  try writer.append(UInt8(ascii: "\""))
  try writer.append(name)
  try writer.append("\":")
  try writer.decimal(value)
}
