// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension SignalSet {
  internal mutating func pass(_ payload: borrowing Span<UInt8>,
                              compatibility: CompatibilityMode,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard NativeDebugControl.capabilities.contains(.passthrough) else {
      throw .unsupported
    }
    let signals = try SignalSet(payload, compatibility: compatibility)
    try writer.append("OK")
    self = signals
  }

  fileprivate init(_ payload: borrowing Span<UInt8>,
                   compatibility: CompatibilityMode? = nil)
      throws(GDBHandlerError) {
    self.init()
    var reader = GDBPacketReader(payload.extracting(0...))
    while reader.empty == false {
      let signal = try reader.hex()
      guard signal <= UInt8.max else {
        throw .malformed
      }
      let native: CInt? = if let compatibility {
        compatibility.native(signal)
      } else {
        CInt(signal)
      }
      guard let native, let number = UInt8(exactly: native) else {
        throw .malformed
      }
      insert(number)
      if reader.empty || reader.consume(UInt8(ascii: ";")) {
        continue
      }
      while reader.consume(UInt8(ascii: " ")) {
      }
      guard reader.empty else {
        throw .malformed
      }
    }
  }
}

extension GDBRemoteSessionState {
  internal mutating func program(_ payload: borrowing Span<UInt8>,
                                 writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let signals = try SignalSet(payload)
    try writer.append("OK")
    delivery = signals
  }
}
