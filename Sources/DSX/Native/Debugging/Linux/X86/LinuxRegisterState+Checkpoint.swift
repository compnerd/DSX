// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if (os(Android) || os(Linux)) && (arch(i386) || arch(x86_64))
extension LinuxRegisterState {
  internal static let checkpoint: Int = MemoryLayout<UInt>.size

  internal func checkpoint(into output: inout OutputSpan<UInt8>)
      throws(Debuggee.Error) {
    try output.append(general.origin, size: LinuxRegisterState.checkpoint)
  }

  internal mutating func checkpoint(_ bytes: borrowing Span<UInt8>)
      throws(Debuggee.Error) {
    general.origin = try bytes.register(as: type(of: general.origin))
  }
}
#endif
