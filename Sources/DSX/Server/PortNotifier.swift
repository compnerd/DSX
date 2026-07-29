// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal enum PortNotifier {
  internal static func write(_ port: UInt16?,
                             to notification: borrowing PortNotification)
      throws(TransportError) {
    guard let port else {
      throw .notification
    }
    switch notification {
    case .descriptor(let descriptor):
      try send(port, endpoint: .descriptor(descriptor))
    case .pipe(let path):
      try send(port, endpoint: .notification(path))
    case .file(let path):
      try file(port, path: path)
    }
  }
}

private func send(_ port: UInt16, endpoint: StreamEndpoint)
    throws(TransportError) {
  let stream = try Stream(endpoint)
  var failure: TransportError?
  withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 6) { buffer in
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
      do throws(TransportError) {
        let written = try stream.write(bytes.extracting(offset...))
        guard written > 0 else {
          throw .write(0)
        }
        offset += written
      } catch {
        failure = error
        return
      }
    }
  }
  if let failure {
    throw failure
  }
}

private func file(_ port: UInt16, path: String) throws(TransportError) {
  let descriptor: CInt
  do throws(LogError) {
    descriptor = try LogSystem.open(path, append: false)
  } catch {
    switch error {
    case .open(let code):
      throw .open(code)
    }
  }
  defer {
    LogSystem.close(descriptor)
  }
  try send(port, endpoint: .descriptor(descriptor))
}
