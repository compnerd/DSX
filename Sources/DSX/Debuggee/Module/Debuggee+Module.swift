// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Debuggee.Module {
  internal init(path: String, architecture: String? = nil)
      throws(Debuggee.Error) {
    let path = try NativeFileSystem.canonical(path)
    let storage = try NativeMappedFile(path)
    try self.init(path: path, bytes: storage.span(), architecture: architecture)
  }
}
