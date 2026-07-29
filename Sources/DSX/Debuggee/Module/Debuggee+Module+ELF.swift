// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux) || os(FreeBSD) || os(OpenBSD)
extension Debuggee.Module {
  internal init(path: String, bytes: consuming Span<UInt8>,
                architecture _: String?) throws(Debuggee.Error) {
    guard let module = try ELFModule(bytes) else {
      throw .process
    }
    self = try module.module(path)
  }
}
#endif
