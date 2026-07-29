// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal func process(_ name: String,
                      accepting: (ProcessIdentifier) -> Bool = { _ in true })
    throws(Debuggee.Error) -> ProcessIdentifier? {
  var processes = try NativeProcessCursor()
  var selected: ProcessIdentifier?
  while true {
    let info: Debuggee.Process.Info
    do {
      guard let next = try processes.next() else {
        return selected
      }
      info = next
    } catch .process, .access {
      continue
    } catch {
      throw error
    }
    guard info.name == name, accepting(info.process) else {
      continue
    }
    if let selected, selected.rawValue <= info.process.rawValue {
      continue
    }
    selected = info.process
  }
}
