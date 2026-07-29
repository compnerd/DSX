// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum StreamEndpoint: Sendable {
  case descriptor(CInt)
  case device(String)
  case notification(String)
  case pipe(String)
}

extension NativeStreamSystem {
  internal static func read(_ handle: Handle,
                            into bytes: inout OutputSpan<UInt8>)
      throws(TransportError) {
    try bytes
      .withUnsafeMutableBufferPointer { data, offset throws(TransportError) in
      let base = data.baseAddress!.advanced(by: offset)
      offset += try receive(handle, base, data.count - offset)
    }
  }

  internal static func write(_ handle: Handle, _ bytes: borrowing Span<UInt8>)
      throws(TransportError) -> Int {
    if bytes.isEmpty {
      return 0
    }
    return try bytes.withUnsafeBytes { bytes throws(TransportError) in
      try transmit(handle, bytes.baseAddress!, bytes.count)
    }
  }
}
