// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

extension Span where Element == Debuggee.Continuation {
  internal func action(_ thread: ProcessThreadIdentifier)
      -> Debuggee.Continuation? {
    action(thread.process, thread: thread)
  }

  internal func action(_ process: ProcessIdentifier,
                       thread: ProcessThreadIdentifier? = nil)
      -> Debuggee.Continuation? {
    for index in 0 ..< count {
      let action = self[index]
      let matches = switch action.selection {
      case .thread(let identifier): identifier == thread
      case .process(let identifier): identifier == process
      case .all, .any: true
      }
      if matches {
        return action
      }
    }
    return nil
  }
}
