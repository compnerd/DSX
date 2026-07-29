// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBAddressPacket {
  internal static func tls(_ payload: borrowing Span<UInt8>,
                           session: inout DebugSession,
                           state: inout GDBRemoteSessionState,
                           writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    throw .unsupported
  }
}

extension GDBAddressPacket {
  internal static func tib(_ payload: borrowing Span<UInt8>,
                           session: inout DebugSession,
                           writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard DebugCapabilities.current.contains(.tib) else {
      throw .unsupported
    }
    let selection =
        try GDBThreadIdentifier.parse(payload, debuggee: session.debuggee)
    guard case .thread(let thread) = selection else {
      throw .debuggee(.thread)
    }
    try writer.hex(translate(thread.tib).rawValue)
  }
}
