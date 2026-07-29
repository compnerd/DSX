// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension DebugSession {
  internal mutating func info(_ process: ProcessIdentifier)
      throws(Debuggee.Error) -> Debuggee.Process.Info {
    let info = try process.info
    debuggee.update(info)
    return info
  }

  internal func image(_ process: ProcessIdentifier) throws(Debuggee.Error)
      -> Debuggee.Image {
    guard let image = try process.image else {
      throw .process
    }
    return image
  }

  internal mutating func refresh(_ process: ProcessIdentifier)
      throws(Debuggee.Error) {
    var threads = try process.threads
    threads.order { lhs, rhs in
      lhs.thread.rawValue < rhs.thread.rawValue
    }
    debuggee.refresh(process, threads: threads.span)
  }
}
