// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(FreeBSD) || os(OpenBSD)
internal import Glibc

extension BSDDebugControl {
  internal mutating func launch(_ config: borrowing Debuggee.Launch)
      throws(Debuggee.Error) -> ProcessIdentifier {
    guard config.aslr else {
      throw .unsupported
    }
    let descriptors = UnixDescriptors(reader: -1, writer: -1)
    let child = try config.spawn(descriptors: descriptors)
    let process = ProcessIdentifier(rawValue: UInt64(child))
    self.process = process
    return process
  }
}
#endif
