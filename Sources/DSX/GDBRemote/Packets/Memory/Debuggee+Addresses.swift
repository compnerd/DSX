// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal borrowing func tib(_ payload: borrowing Span<UInt8>,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard DebugCapabilities.current.contains(.tib) else {
      throw .unsupported
    }
    let selection = try Debuggee.Thread.Selection(payload, debuggee: self)
    guard case .thread(let thread) = selection else {
      throw .debuggee(.thread)
    }
    try writer.hex(translate(thread.tib).rawValue)
  }
}
