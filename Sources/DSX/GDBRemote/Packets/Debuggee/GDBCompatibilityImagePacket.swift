// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum GDBFileLoadAddressPacket {
  internal static func handle(_ payload: borrowing Span<UInt8>,
                              session: inout DebugSession,
                              state: inout GDBRemoteSessionState,
                              writer: inout GDBPacketWriter)
      throws(GDBHandlerError) {
    let process = try GDBPacketScope.process(state.selection.general,
                                             debuggee: session.debuggee)
    let images = try translate(process.images(.name))
    let address = try address(payload, debuggee: session.debuggee,
                              images: images.span, state: state)
    guard let address else {
      throw .code(GDBErrorCode.failure)
    }
    try writer.hex(address.rawValue)
  }

  internal static func address(_ payload: borrowing Span<UInt8>,
                               debuggee: borrowing Debuggee,
                               images: borrowing Span<Debuggee.Image>,
                               state: borrowing GDBRemoteSessionState)
      throws(GDBHandlerError) -> Debuggee.Address? {
    try validate(payload)
    let process =
        try GDBPacketScope.process(state.selection.general, debuggee: debuggee)
    let name = debuggee.name(process)
    let capacity = payload.count / 2
    return withUnsafeTemporaryAllocation(of: UInt8.self,
                                         capacity: capacity) { buffer in
      for index in 0 ..< buffer.count {
        let offset = index * 2
        let high = GDBPacketReader.digit(payload[offset]) ?? 0
        let low = GDBPacketReader.digit(payload[offset + 1]) ?? 0
        buffer[index] = high << 4 | low
      }
      let path = buffer.span
      for index in 0 ..< images.count {
        let image = images[index]
        if matches(path, image: image, name: name) {
          return image.base
        }
      }
      return nil
    }
  }
}

private func matches(_ path: borrowing Span<UInt8>,
                     image: borrowing Debuggee.Image,
                     name: borrowing String?) -> Bool {
  if NativeFileSystem.matches(path, image.path, component: false) {
    return true
  }
  if image.path.isEmpty {
    guard image.main else {
      return false
    }
    return switch name {
    case .some(let name):
      NativeFileSystem.matches(path, name, component: true)
    case .none: false
    }
  }
  return NativeFileSystem.matches(path, image.path, component: true)
}

private func validate(_ path: borrowing Span<UInt8>) throws(GDBHandlerError) {
  guard path.count % 2 == 0 else {
    throw .malformed
  }
  var index = 0
  while index < path.count {
    guard case .some = GDBPacketReader.digit(path[index]),
        case .some = GDBPacketReader.digit(path[index + 1]) else {
      throw .malformed
    }
    index += 2
  }
}
