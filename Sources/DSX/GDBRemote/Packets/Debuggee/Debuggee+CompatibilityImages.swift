// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee {
  internal borrowing func load(_ payload: borrowing Span<UInt8>,
                               state: borrowing GDBRemoteSessionState,
                               writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try state.selection.general.process(in: self)
    let images = try translate(process.images(.name))
    let address = try address(payload, images: images.span, state: state)
    guard let address else {
      throw .code(GDBErrorCode.failure)
    }
    try writer.hex(address.rawValue)
  }

  internal borrowing func address(_ payload: borrowing Span<UInt8>,
                                  images: borrowing Span<Debuggee.Image>,
                                  state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) -> Debuggee.Address? {
    let process = try state.selection.general.process(in: self)
    let name = name(process)
    let capacity = payload.count / 2
    return try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                             { raw throws(GDBHandlerError) in
      var decoded = OutputSpan(buffer: raw, initializedCount: 0)
      try decoded.decode(payload)
      let path = decoded.span
      for index in 0 ..< images.count {
        let image = images[index]
        if image.matches(path, name: name) {
          return image.base
        }
      }
      return nil
    })
  }
}

extension Debuggee.Image {
  fileprivate borrowing func matches(_ path: borrowing Span<UInt8>,
                                     name: borrowing String?) -> Bool {
    if NativeFileSystem.matches(path, self.path, component: false) {
      return true
    }
    if self.path.isEmpty {
      guard main else {
        return false
      }
      return switch name {
      case .some(let name):
        NativeFileSystem.matches(path, name, component: true)
      case .none: false
      }
    }
    return NativeFileSystem.matches(path, self.path, component: true)
  }
}
