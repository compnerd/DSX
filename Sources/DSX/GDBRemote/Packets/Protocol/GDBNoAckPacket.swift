// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBNoAckPacket {
  internal static func handle(state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) -> GDBPacketDisposition {
    guard state.negotiation.supported.contains(.noack) else {
      throw .unsupported
    }
    state.negotiation.enable(.noack)
    state.negotiation.acknowledgements = false
    try writer.append("OK")
    return .reply
  }
}
