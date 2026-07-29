// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension PortNotification {
  internal func write(_ port: UInt16?) throws(TransportError) {
    guard let port else {
      throw .notification
    }
    switch self {
    case .descriptor(let descriptor):
      try send(port, endpoint: .descriptor(descriptor))
    case .pipe(let path):
      try send(port, endpoint: .notification(path))
    case .file(let path):
      try DSX::file(port, path: path)
    }
  }
}

private func send(_ port: UInt16, endpoint: StreamEndpoint)
    throws(TransportError) {
  let stream = try Stream(endpoint)
  try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 6,
                                    { buffer throws(TransportError) in
    var value = port
    var count = 1
    buffer[5] = 0x0a
    repeat {
      count += 1
      buffer[6 - count] = UInt8(value % 10) + 0x30
      value /= 10
    } while value > 0
    let bytes = buffer.span.extracting((6 - count)...)
    var offset = 0
    while offset < bytes.count {
      let written = try stream.write(bytes.extracting(offset...))
      guard written > 0 else {
        throw .write(0)
      }
      offset += written
    }
  })
}

private func file(_ port: UInt16, path: String) throws(TransportError) {
  let descriptor: CInt
  do throws(LogError) {
    descriptor = try NativeLog.open(path, append: false)
  } catch {
    switch error {
    case .open(let code):
      throw .open(code)
    }
  }
  defer {
    NativeLog.close(descriptor)
  }
  try send(port, endpoint: .descriptor(descriptor))
}
