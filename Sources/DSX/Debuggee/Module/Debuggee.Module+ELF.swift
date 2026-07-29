// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Android) || os(Linux) || os(FreeBSD) || os(OpenBSD)
extension Debuggee.Module {
  internal init(path: String, bytes: consuming Span<UInt8>,
                architecture _: String?) throws(Debuggee.Error) {
    guard let module = try ELFModule(bytes) else {
      throw .process
    }
    try self.init(module, path: path)
  }
}
#endif

extension Debuggee.Module {
  internal init(_ module: borrowing ELFModule, path: String)
      throws(Debuggee.Error) {
    let identity = try Debuggee.Module.Identity.unique(module.identifier)
    let architecture = try module.architecture
    self.init(path: path, identity: identity, architecture: architecture,
              base: Debuggee.Address(rawValue: 0), size: module.size)
  }
}
