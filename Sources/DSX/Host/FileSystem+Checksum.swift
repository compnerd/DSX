// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension FileSystem {
  private typealias Failure = Debuggee.Error

  internal mutating func checksum(_ path: String, directory: String?)
      throws(Debuggee.Error) -> InlineArray<16, UInt8> {
    let file = try open(path, directory: directory, options: [.read], mode: 0)
    defer {
      do throws(Debuggee.Error) {
        try close(file)
      } catch {
        DSX.log("failed to close checksum input: \(error)", level: .warning,
                channel: .system)
      }
    }
    var checksum = try MD5Checksum()
    var offset: UInt64 = 0
    let capacity = Configuration.FileTransferCapacity
    while true {
      let count =
          try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity,
                                            { buffer throws(Failure) in
        var output = OutputSpan(buffer: buffer, initializedCount: 0)
        try read(file, offset: offset, size: buffer.count, into: &output)
        try checksum.update(output.span)
        return output.count
      })
      guard count > 0 else {
        break
      }
      offset += UInt64(count)
    }
    return try checksum.finish()
  }
}
