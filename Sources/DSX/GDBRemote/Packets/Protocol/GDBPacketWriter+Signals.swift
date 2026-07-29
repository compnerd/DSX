// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension GDBPacketWriter {
  internal mutating func signals(_ payload: borrowing Span<UInt8>)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    try append(UInt8(ascii: "["))
    var first = true
    try SignalCatalog.visit { signal throws(GDBHandlerError) in
      try emit(signal: signal, first: &first)
    }
    try append(UInt8(ascii: "]"))
  }

  @inline(__always)
  internal mutating func emit(signal: Int, first: inout Bool)
      throws(GDBHandlerError) {
    if first {
      first = false
    } else {
      try append(UInt8(ascii: ","))
    }
    try append("{\"signo\":")
    try decimal(UInt64(signal))
    try append(",\"name\":\"")
    switch SignalCatalog.name(signal) {
    case .fixed(let name):
      try append(name)
    case .realtime(let offset):
      try append("SIGRTMIN")
      if offset > 0 {
        try append(UInt8(ascii: "+"))
        try decimal(UInt64(offset))
      }
    }
    let policy = SignalCatalog.policy(signal)
    try append("\",\"suppress\":")
    try append(policy & SignalCatalog.kSuppress > 0 ? "true" : "false")
    try append(",\"stop\":")
    try append(policy & SignalCatalog.kStop > 0 ? "true" : "false")
    try append(",\"notify\":")
    try append(policy & SignalCatalog.kNotify > 0 ? "true" : "false")
    try append(UInt8(ascii: "}"))
  }
}
