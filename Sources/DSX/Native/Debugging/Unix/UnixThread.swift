// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if !os(Windows)
internal enum UnixThread {
  internal typealias Snapshot = Array<ProcessThreadIdentifier>
}

extension UnixThread {
  internal static func snapshot(_ processes: borrowing Span<Debuggee.Process>)
      throws(Debuggee.Error) -> Snapshot {
    var identifiers = Array<ProcessThreadIdentifier>()
    for index in 0 ..< processes.count {
      try identifiers.append(contentsOf: processes[index].identifier.threads)
    }
    return identifiers
  }

  internal static func identifiers(_ process: ProcessIdentifier,
                                   snapshot: borrowing Snapshot)
      throws(Debuggee.Error) -> Snapshot {
    var identifiers = Snapshot()
    for index in 0 ..< snapshot.count {
      if snapshot[index].process == process {
        identifiers.append(snapshot[index])
      }
    }
    return identifiers
  }
}
#endif
