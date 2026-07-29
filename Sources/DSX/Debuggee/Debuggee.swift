// Copyright © 2026 Saleem Abdulrasool <compnerd@compnerd.org>. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause

internal struct ProcessIdentifier: Equatable, Sendable {
  internal let rawValue: UInt64

  internal init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

internal struct ThreadIdentifier: Equatable, Sendable {
  internal let rawValue: UInt64

  internal init(rawValue: UInt64) {
    self.rawValue = rawValue
  }
}

internal struct ProcessThreadIdentifier: Equatable, Sendable {
  internal let process: ProcessIdentifier
  internal let thread: ThreadIdentifier

  internal init(process: ProcessIdentifier, thread: ThreadIdentifier) {
    self.process = process
    self.thread = thread
  }
}

internal enum ReadStatus: Equatable, Sendable {
  case last
  case more
}

internal struct Debuggee: Sendable {
  internal var processes: Array<Process>

  internal init(processes: consuming Array<Process> = []) {
    self.processes = consume processes
  }
}

extension Debuggee {
  internal struct Address: Equatable, Sendable {
    internal let rawValue: UInt64

    internal init(rawValue: UInt64) {
      self.rawValue = rawValue
    }
  }
}
