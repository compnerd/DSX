// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal borrowing func context(_ payload: borrowing Span<UInt8>,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard let layout = try Debuggee.Thread.Layout(payload) else {
      return try writer.append("OK")
    }
    guard let thread = debuggee.resolve(layout.thread) else {
      throw .debuggee(.thread)
    }
    try writer.emit(translate(thread.context(layout)))
  }
}

extension Debuggee.Thread.Layout {
  @inline(__always)
  internal init?(_ payload: borrowing Span<UInt8>) throws(GDBHandlerError) {
    var reader = GDBPacketReader(payload.extracting(0...))
    guard reader.consume(UInt8(ascii: ":")) else {
      throw .malformed
    }
    if reader.empty {
      return nil
    }
    guard reader.token(UInt8(ascii: "{")) else {
      throw .malformed
    }
    var thread: UInt64?
    var address: UInt64?
    var base: UInt64?
    var size: UInt64?
    var quality: UInt64?
    let absolute: StaticString = "plo_pthread_tsd_base_address_offset"
    while true {
      let key = try reader.quoted()
      guard reader.token(UInt8(ascii: ":")) else {
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
      case () where reader.matches(key, value: "dti_qos_class_index"):
        quality = value
      default:
        break
      }
      if reader.token(UInt8(ascii: "}")) {
        break
      }
      guard reader.token(UInt8(ascii: ",")) else {
        throw .malformed
      }
    }
    guard reader.empty, let thread else {
      throw .malformed
    }
    self.init(thread: ThreadIdentifier(rawValue: thread), address: address,
              base: base, size: size, quality: quality)
  }
}

extension GDBPacketWriter {
  internal mutating func emit(_ context: borrowing Debuggee.Thread.Context)
      throws(GDBHandlerError) {
    try append(UInt8(ascii: "{"))
    var first = true
    try field("pthread_t", value: context.pthread, first: &first)
    try field("tsd_address", value: context.storage, first: &first)
    try field("dispatch_queue_t", value: context.queue, first: &first)
    if let quality = context.quality {
      if first == false {
        try append(UInt8(ascii: ","))
      }
      try append("\"requested_qos\":{\"enum_value\":")
      try decimal(UInt64(quality.value))
      try append(",\"constant_name\":\"")
      try append(quality.constant)
      try append("\",\"printable_name\":\"")
      try append(quality.name)
      try append("\"}")
    }
    try append(UInt8(ascii: "}"))
  }

  private mutating func field(_ name: StaticString, value: UInt64?,
                              first: inout Bool) throws(GDBHandlerError) {
    guard let value else {
      return
    }
    if first {
      first = false
    } else {
      try append(UInt8(ascii: ","))
    }
    try append(UInt8(ascii: "\""))
    try append(name)
    try append("\":")
    try decimal(value)
  }
}
