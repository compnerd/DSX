// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct GDBRemoteThreadOptions: Sendable {
  private typealias Record = (thread: ProcessThreadIdentifier, options: UInt64)

  private var records = Array<Record>()

  internal mutating func set(_ selection: Debuggee.Thread.Selection,
                             options: UInt64, debuggee: borrowing Debuggee) {
    for process in debuggee.processes {
      for thread in process.threads
          where applies(selection, thread: thread.identifier) {
        assign(thread.identifier, options: options)
      }
    }
  }

  internal borrowing func contains(_ thread: ProcessThreadIdentifier,
                                   option: UInt64) -> Bool {
    for record in records where record.thread == thread {
      return record.options & option == option
    }
    return false
  }

  internal mutating func remove(_ thread: ProcessThreadIdentifier) {
    records.removeAll { record in
      record.thread == thread
    }
  }

  internal mutating func remove(_ process: ProcessIdentifier) {
    records.removeAll { record in
      record.thread.process == process
    }
  }

  private mutating func assign(_ thread: ProcessThreadIdentifier,
                               options: UInt64) {
    for index in records.indices where records[index].thread == thread {
      records[index].options = options
      return
    }
    records.append((thread: thread, options: options))
  }

  private borrowing func applies(_ selection: Debuggee.Thread.Selection,
                                 thread: ProcessThreadIdentifier) -> Bool {
    switch selection {
    case .all, .any: true
    case .process(let process): process == thread.process
    case .thread(let selected): selected == thread
    }
  }
}
