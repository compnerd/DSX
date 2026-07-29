// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

/// Walks the native frame chain without interpreting it as a protocol reply.
internal struct NativeStack {
  internal static let size: Int = ABI.width.bytes * 2

  private let process: ProcessIdentifier
  private var frame: UInt64
  private var remaining = Configuration.Stack.Frames

  internal init(_ process: ProcessIdentifier, frame: UInt64) {
    self.process = process
    self.frame = frame
  }

  @inline(__always)
  internal mutating func next(in session: borrowing DebugSession,
                              into output: inout OutputSpan<UInt8>) -> UInt64? {
    let width = ABI.width.bytes
    let size = NativeStack.size
    guard ABI.frame, remaining > 0, frame > 0, frame % UInt64(width) == 0,
        frame <= UInt64.max - UInt64(size) else {
      return nil
    }
    remaining -= 1
    let address = frame
    frame = 0
    do throws(Debuggee.Error) {
      try session.read(process, address: Debuggee.Address(rawValue: address),
                       size: size, into: &output)
      guard output.count == size else {
        return nil
      }
      let next =
          try output.span.integer(at: 0, count: width,
                                  little: ABI.endian == .little)
      // Older frames grow toward higher addresses on these ABIs. Requiring
      // progress rejects cycles without allocating a visited-address set.
      if next > address {
        frame = next
      }
      return address
    } catch {
      return nil
    }
  }
}
