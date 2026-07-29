// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !((os(Android) || os(Linux)) && (arch(i386) || arch(x86_64)))
extension NativeRegisterState {
  internal static let checkpoint: Int = 0

  internal func checkpoint(into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
  }

  internal mutating func checkpoint(_ bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    guard bytes.isEmpty else {
      throw .register
    }
  }
}
#endif
