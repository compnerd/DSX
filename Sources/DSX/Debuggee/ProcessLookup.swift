// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct ProcessLookup: ~Copyable {
  private let name: String
  private var processes: NativeProcessCursor

  internal init(_ name: consuming String) throws(Debuggee.Error) {
    self.name = consume name
    processes = try NativeProcessCursor()
  }

  @inline(never)
  internal mutating func next() throws(Debuggee.Error) -> ProcessIdentifier? {
    while true {
      let info: Debuggee.Process.Info
      do {
        guard let next = try processes.next() else {
          return nil
        }
        info = next
      } catch .process, .access {
        continue
      } catch {
        throw error
      }
      if info.matches(name: name) {
        return info.process
      }
    }
  }

  internal mutating func first(excluding: borrowing Array<ProcessIdentifier>)
      throws(Debuggee.Error) -> ProcessIdentifier? {
    var selected: ProcessIdentifier?
    while let process = try next() {
      if excluding.contains(process) {
        continue
      }
      if let selected, selected.rawValue <= process.rawValue {
        continue
      }
      selected = process
    }
    return selected
  }
}

extension Debuggee.Process.Info {
  internal func matches(name: String) -> Bool {
    if self.name == name {
      return true
    }
    let path = self.name.utf8Span.span
    let name = name.utf8Span.span
    guard name.count > 0, path.count > name.count else {
      return false
    }
    let start = path.count - name.count
    let separator = path[start - 1]
    guard NativeFileSystem.separates(separator) else {
      return false
    }
    for index in 0 ..< name.count {
      let byte = name[index]
      guard byte == path[start + index],
          NativeFileSystem.separates(byte) == false else {
        return false
      }
    }
    return true
  }
}

extension ProcessIdentifier {
  internal init(resolving value: String) throws(Debuggee.Error) {
    if let identifier = value.utf8Span.span.decimal() {
      self.init(rawValue: identifier)
      return
    }
    var lookup = try ProcessLookup(value)
    guard let process = try lookup.first(excluding: []) else {
      throw .process
    }
    self = process
  }
}
