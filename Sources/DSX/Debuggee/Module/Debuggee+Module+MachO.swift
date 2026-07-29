// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
extension Debuggee.Module {
  internal init(path: String, bytes: consuming Span<UInt8>,
                architecture: String?) throws(Debuggee.Error) {
    if let module = try ELFModule(copy bytes) {
      self = try module.module(path)
      return
    }
    guard let module = try MachOModule(bytes, requested: architecture) else {
      throw .process
    }
    let identity = try module.identity
    let architecture = try module.architecture
    self.init(path: path, identity: identity, architecture: architecture,
              base: Debuggee.Address(rawValue: module.offset),
              size: module.size)
  }
}

#endif
