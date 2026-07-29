// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(Windows)
extension Debuggee.Module {
  internal init(path: String, bytes: consuming Span<UInt8>,
                architecture _: String?) throws(Debuggee.Error) {
    let module = try PEModule(copy bytes)
    let identity: Debuggee.Module.Identity? = if let module {
      try? .unique(module.identifier)
    } else {
      nil
    }
    let architecture = if let module {
      try module.architecture
    } else {
      try PEModule.architecture(integer(bytes, at: 0, count: 2))
    }
    self.init(path: path, identity: identity, architecture: architecture,
              base: Debuggee.Address(rawValue: 0), size: UInt64(bytes.count))
  }
}

#endif
