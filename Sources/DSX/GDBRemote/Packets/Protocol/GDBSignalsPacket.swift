// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBSignalsPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    try writer.append(UInt8(ascii: "["))
    var first = true
    try SignalCatalog.visit { signal throws(GDBHandlerError) in
      try write(signal, first: &first, writer: &writer)
    }
    try writer.append(UInt8(ascii: "]"))
  }

  @inline(__always)
  internal static func write(_ signal: Int, first: inout Bool,
                             writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    if first {
      first = false
    } else {
      try writer.append(UInt8(ascii: ","))
    }
    try writer.append("{\"signo\":")
    try writer.decimal(UInt64(signal))
    try writer.append(",\"name\":\"")
    switch SignalCatalog.name(signal) {
    case .fixed(let name):
      try writer.append(name)
    case .realtime(let offset):
      try writer.append("SIGRTMIN")
      if offset > 0 {
        try writer.append(UInt8(ascii: "+"))
        try writer.decimal(UInt64(offset))
      }
    }
    let policy = SignalCatalog.policy(signal)
    try writer.append("\",\"suppress\":")
    try writer.append(policy & SignalCatalog.kSuppress > 0 ? "true" : "false")
    try writer.append(",\"stop\":")
    try writer.append(policy & SignalCatalog.kStop > 0 ? "true" : "false")
    try writer.append(",\"notify\":")
    try writer.append(policy & SignalCatalog.kNotify > 0 ? "true" : "false")
    try writer.append(UInt8(ascii: "}"))
  }
}
