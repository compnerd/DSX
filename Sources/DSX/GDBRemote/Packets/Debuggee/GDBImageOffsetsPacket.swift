// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal borrowing func offsets(_ payload: borrowing Span<UInt8>,
                                  state: borrowing GDBRemoteSessionState,
                                  writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    guard payload.isEmpty else {
      throw .malformed
    }
    let process = try state.selection.general.process(in: debuggee)
    let image = try translate(image(process))
    let offsets = try translate(image.offsets)
    try writer.emit(offsets)
  }
}

extension GDBPacketWriter {
  internal mutating func emit(_ offsets: Debuggee.ImageOffsets)
      throws(GDBHandlerError) {
    switch offsets {
    case .sections(let text, let data):
      try append("Text=")
      try hex(text)
      try append(";Data=")
      try hex(data)
      try append(";Bss=")
      try hex(data)
    case .segments(let text, let data):
      try append("TextSeg=")
      try hex(text.rawValue)
      if let data {
        try append(";DataSeg=")
        try hex(data.rawValue)
      }
    }
  }
}
