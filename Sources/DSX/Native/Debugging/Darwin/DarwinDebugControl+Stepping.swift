// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

#if os(anyAppleOS)
extension DarwinDebugControl {
  internal mutating func step(_ actions: borrowing Debuggee.Continuations,
                              process: ProcessIdentifier,
                              threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    try finish(threads)
    for index in 0 ..< threads.count {
      let candidate = threads[index]
      let thread = try identity(candidate)
      let identifier = ProcessThreadIdentifier(process: process, thread: thread)
      let action = actions.action(identifier)
      guard action?.operation == .step else {
        continue
      }
      try DarwinDebugControl.step(candidate, enabled: true)
      steps.append(identifier)
    }
  }

  internal mutating func finish(_ threads: borrowing DarwinThreadList)
      throws(Debuggee.Error) {
    var pending = steps.count
    while pending > 0 {
      pending -= 1
      let identifier = steps[pending]
      for index in 0 ..< threads.count {
        let candidate = threads[index]
        guard try identity(candidate) == identifier.thread else {
          continue
        }
        try DarwinDebugControl.step(candidate, enabled: false)
        break
      }
      steps.remove(at: pending)
    }
  }
}
#endif
