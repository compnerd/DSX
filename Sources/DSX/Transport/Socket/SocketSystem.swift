// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct NetworkEndpoint: Sendable {
  internal let host: String?
  internal let port: UInt16

  internal init(host: consuming String?, port: UInt16) {
    self.host = consume host
    self.port = port
  }
}

internal struct UnixEndpoint: Sendable {
  internal let path: String

  internal init(path: consuming String) {
    self.path = consume path
  }
}

internal enum SocketBinding: Sendable {
  case network(UInt16)
  case unix(String)

  internal var path: String? {
    switch self {
    case .network: nil
    case .unix(let path): path
    }
  }
}

extension NativeSocketSystem {
  internal static func connect(_ endpoint: NetworkEndpoint)
      throws(TransportError) -> Handle {
    try open(endpoint, listening: false).handle
  }

  internal static func listen(_ endpoint: NetworkEndpoint)
      throws(TransportError) -> (handle: Handle, port: UInt16) {
    try open(endpoint, listening: true)
  }

  internal static func connect(_ endpoint: UnixEndpoint) throws(TransportError)
      -> Handle {
    try open(endpoint, listening: false)
  }

  internal static func listen(_ endpoint: UnixEndpoint) throws(TransportError)
      -> Handle {
    try open(endpoint, listening: true)
  }

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
