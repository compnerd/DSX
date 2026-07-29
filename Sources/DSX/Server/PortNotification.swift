// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension PortNotification {
  internal func write(_ port: UInt16?) throws(TransportError) {
    guard let port else {
      throw .notification
    }
    let endpoint: StreamEndpoint
    switch self {
    case .descriptor(let descriptor):
      endpoint = .descriptor(descriptor)
    case .pipe(let path):
      endpoint = .notification(path)
    case .file(let path):
      let descriptor: CInt
      do throws(LogError) {
        descriptor = try NativeLog.open(path, append: false)
      } catch {
        switch error {
        case .open(let code): throw .open(code)
        }
      }
      endpoint = .descriptor(descriptor)
    }
    defer {
      if case .file = self, case .descriptor(let descriptor) = endpoint {
        NativeLog.close(descriptor)
      }
    }
    try Stream(endpoint).emit(port)
  }
}

extension Stream {
  fileprivate borrowing func emit(_ port: UInt16) throws(TransportError) {
    var buffer = InlineArray<6, UInt8>(repeating: 0)
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
      let written = try write(bytes.extracting(offset...))
      guard written > 0 else {
        throw .write(0)
      }
      offset += written
    }
  }
}
